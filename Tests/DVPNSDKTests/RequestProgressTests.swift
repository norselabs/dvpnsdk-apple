//
//  RequestProgressTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Testing

/// `RequestProgress` over real connections to a loopback server: URLSession reports a body sent or an answer begun only
/// over one.
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

    private func send(method: String, body: Data?, to url: URL, watchedBy progress: RequestProgress) -> Task<Void, any Error> {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        return Task { _ = try await URLSession(configuration: .ephemeral).data(for: request, delegate: progress) }
    }
}
