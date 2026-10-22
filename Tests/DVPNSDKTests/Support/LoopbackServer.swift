//
//  LoopbackServer.swift
//  DVPNSDK
//

import Foundation
import Network
import Synchronization

/// An HTTP server on 127.0.0.1, for a test that needs a real connection: URLSession reports a request's body as sent,
/// or its answer as begun, only over one, never through a `URLProtocol`. Once a whole request is in, it sends
/// `answerStart` (nothing, by default), and nothing more.
final class LoopbackServer: Sendable {
    static let host = "127.0.0.1"

    private struct State {
        var connections: [NWConnection] = []
        var requests = 0
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LoopbackServer")
    private let answerStart: Data
    private let state = Mutex(State())

    /// How many whole requests came in.
    var requestCount: Int { state.withLock { $0.requests } }

    init(answerStart: String = "") throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        self.answerStart = Data(answerStart.utf8)
    }

    /// Starts listening, and returns the server's URL.
    func start() async throws -> URL {
        listener.newConnectionHandler = { [self] connection in accept(connection) }
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint.Port, any Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port ?? .any)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "http://\(Self.host):\(port.rawValue)")!
    }

    func stop() {
        listener.cancel()
        state.withLock { $0.connections }.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        state.withLock { $0.connections.append(connection) }
        connection.start(queue: queue)
        receive(on: connection, received: Data())
    }

    /// Reads until the request is whole, its headers and the body they announce, then sends the answer's start.
    private func receive(on connection: NWConnection, received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] content, _, isComplete, error in
            let received = received + (content ?? Data())
            guard Self.isWhole(received) else {
                if !isComplete, error == nil { receive(on: connection, received: received) }
                return
            }
            state.withLock { $0.requests += 1 }
            if !answerStart.isEmpty { connection.send(content: answerStart, completion: .idempotent) }
        }
    }

    private static func isWhole(_ request: Data) -> Bool {
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let length = String(decoding: request[..<end.lowerBound], as: UTF8.self)
            .lowercased()
            .split(separator: "\r\n")
            .first { $0.hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        return request.distance(from: end.upperBound, to: request.endIndex) >= length
    }
}
