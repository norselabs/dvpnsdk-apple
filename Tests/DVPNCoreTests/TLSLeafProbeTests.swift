//
//  TLSLeafProbeTests.swift
//  DVPNCore
//
//  Local end-to-end checks of the probe against NWListener servers on the loopback interface.
//  macOS only: the in-memory PKCS#12 import the TLS server needs is a macOS/iOS API.
//

#if os(macOS)
@testable import DVPNXRayCore
import Foundation
import Network
import os
import Security
import Testing

struct TLSLeafProbeTests {
    private let queue = DispatchQueue(label: "com.example.vpn.tests.tls-leaf-probe")

    @Test(.enabled(if: TestFixtures.canImportIdentity))
    func observesLeafPinOfLocalTLSServer() async throws {
        let identity = try TestFixtures.selfSignedIdentity()
        let tlsOptions = NWProtocolTLS.Options()
        let secIdentity = try #require(sec_identity_create(identity))
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        let server = try LocalServer(parameters: NWParameters(tls: tlsOptions), queue: queue)
        let port = try await server.start()
        defer { server.stop() }

        let pin = try await TLSLeafProbe.observeLeafSHA256(host: "127.0.0.1", port: port, serverName: "localhost", timeout: 5)
        #expect(pin == TestFixtures.selfSignedPin)
    }

    @Test
    func refusedConnectionFails() async throws {
        let port = try await LocalServer.closedPort(queue: queue)
        do {
            _ = try await TLSLeafProbe.observeLeafSHA256(host: "127.0.0.1", port: port, timeout: 3)
            Issue.record("expected a failure")
        } catch let error as TLSLeafProbe.Error {
            guard case .failed = error else { Issue.record("unexpected \(error)"); return }
        }
    }

    @Test
    func plainTCPServerTimesOut() async throws {
        let server = try LocalServer(parameters: .tcp, queue: queue)
        let port = try await server.start()
        defer { server.stop() }

        do {
            _ = try await TLSLeafProbe.observeLeafSHA256(host: "127.0.0.1", port: port, timeout: 1)
            Issue.record("expected a timeout")
        } catch let error as TLSLeafProbe.Error {
            #expect(error == .timedOut(host: "127.0.0.1", port: port))
        }
    }

    @Test
    func invalidPortIsRejectedUpFront() async {
        do {
            _ = try await TLSLeafProbe.observeLeafSHA256(host: "127.0.0.1", port: 0)
            Issue.record("expected a failure")
        } catch {
            #expect(error as? TLSLeafProbe.Error == .invalidPort(host: "127.0.0.1", port: 0))
        }
    }

    @Test
    func ipLiteralsSendNoSNI() {
        #expect(TLSLeafProbe.isIPLiteral("192.0.2.10"))
        #expect(TLSLeafProbe.isIPLiteral("::1"))
        #expect(!TLSLeafProbe.isIPLiteral("example.com"))
        #expect(!TLSLeafProbe.isIPLiteral("localhost"))
    }
}

// MARK: - LocalServer

/// An NWListener on an ephemeral loopback port that accepts connections and never writes.
/// `@unchecked`: the listener is driven from its own queue; the test only starts and cancels it.
private final class LocalServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue: DispatchQueue

    init(parameters: NWParameters, queue: DispatchQueue) throws {
        listener = try NWListener(using: parameters, on: .any)
        self.queue = queue
    }

    func start() async throws -> Int {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [queue] connection in
                connection.start(queue: queue)
            }
            listener.stateUpdateHandler = { [self] state in
                let port = listener.port?.rawValue
                switch state {
                case .ready:
                    guard let port, !resumed.withLock({ let was = $0; $0 = true; return was }) else { return }
                    continuation.resume(returning: Int(port))
                case let .failed(error):
                    guard !resumed.withLock({ let was = $0; $0 = true; return was }) else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    /// A loopback port that was just released, so nothing listens on it.
    static func closedPort(queue: DispatchQueue) async throws -> Int {
        let server = try LocalServer(parameters: .tcp, queue: queue)
        let port = try await server.start()
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        return port
    }
}
#endif
