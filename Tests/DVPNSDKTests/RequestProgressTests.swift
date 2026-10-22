//
//  RequestProgressTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Synchronization
import Testing

/// `RequestProgress` over real connections to a loopback server, as URLSession reports a body sent or an answer begun
/// only over one, and its stop.
@Suite(.timeLimit(.minutes(1)))
struct RequestProgressTests {
    /// A server that took the request's body, or began its answer, has started on the request.
    @Test(arguments: [
        ("POST", Data(#"{"name":"value"}"#.utf8), ""),
        ("GET", nil, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{"),
    ])
    func aBodyTakenOrAnAnswerBegunIsAStart(method: String, body: Data?, answerStart: String) async throws {
        let server = try LoopbackServer(answerStart: answerStart)
        let progress = RequestProgress()
        let task = try await send(method: method, body: body, to: server.start(), watchedBy: progress)
        defer {
            task.cancel()
            server.stop()
        }

        try await eventually { progress.hasStarted }
    }

    /// A server that has a request without a body and says nothing has not started on it, as far as the client can see.
    @Test(arguments: ["GET", "POST"])
    func aSilentServerShowsNoStart(method: String) async throws {
        let server = try LoopbackServer()
        let progress = RequestProgress()
        let task = try await send(method: method, body: nil, to: server.start(), watchedBy: progress)
        defer {
            task.cancel()
            server.stop()
        }

        try await eventually { server.requestCount == 1 }
        #expect(!progress.hasStarted)
    }

    /// A stop stops the send's connection, also one attached after it.
    @Test
    func aStopStopsTheSendsConnection() {
        let progress = RequestProgress()
        let stopped = Mutex(0)
        progress.attach { stopped.withLock { $0 += 1 } }
        #expect(!progress.isCancelled)

        progress.cancel()
        #expect(progress.isCancelled)
        #expect(stopped.withLock { $0 } == 1)
        progress.attach { stopped.withLock { $0 += 1 } }
        #expect(stopped.withLock { $0 } == 2)
    }

    /// A start the send marks itself, as an SNI mirror's does, counts.
    @Test
    func aMarkedStartCounts() {
        let progress = RequestProgress()
        #expect(!progress.hasStarted)
        progress.markStarted()
        #expect(progress.hasStarted)
    }

    /// A send stopped before it began is sent nothing: it ends at once, and the server never sees it.
    @Test
    func aSendStoppedBeforeItBeganIsNeverSent() async throws {
        let server = try LoopbackServer()
        let url = try await server.start()
        defer { server.stop() }
        let progress = RequestProgress()
        progress.cancel()

        await #expect(throws: CancellationError.self) {
            try await MirroredTransport.load(URLRequest(url: url), sentToken: nil, on: URLSession(configuration: .ephemeral), progress: progress)
        }
        // Time for a request to arrive, had one been sent.
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requestCount == 0)
    }

    private func send(method: String, body: Data?, to url: URL, watchedBy progress: RequestProgress) -> Task<Void, any Error> {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        return Task { _ = try await URLSession(configuration: .ephemeral).data(for: request, delegate: progress) }
    }
}
