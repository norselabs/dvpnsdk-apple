//
//  RedirectTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Synchronization
import Testing

/// No session of the SDK follows a redirect: an answer that points to another host is the answer, and nothing goes to
/// that host, the device token least of all. The stub records requests by host, so the suite runs serially.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct RedirectTests {
    private struct Target: APITarget {
        var reportsDeviceState = false
        var method = HTTPMethod.get
        var payload = RequestPayload.none
        var path: String { "server" }
    }

    private struct Storage: DeviceTokenProvider {
        var deviceToken: DeviceToken?
    }

    /// An API request, over the shared session or a fresh one, gets the redirect as its answer.
    @Test(arguments: [false, true])
    func anAPIRequestFollowsNoRedirect(requiresFreshConnection: Bool) async throws {
        RedirectStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectStub.self]
        let transport = MirroredTransport(
            configuration: BackendConfiguration(
                backendURL: try #require(URL(string: "https://primary.test")),
                deviceTokenProvider: Storage(deviceToken: DeviceToken(id: "token-id", token: "secret-token"))
            ),
            sessionConfiguration: configuration,
            freshSessionConfiguration: { configuration },
            resolver: MirrorResolver(bootstrap: MirrorsBootstrapService(urls: [], timeout: 1), resolved: nil, probe: { _ in false }),
            isReachable: { true }
        )

        let response = try? await transport.send(
            APIRequest(target: Target(), timeoutInterval: 5, requiresFreshConnection: requiresFreshConnection),
            headers: [:]
        )

        let tokensElsewhere = RedirectStub.tokensSent(to: "elsewhere.test")
        #expect(tokensElsewhere.isEmpty, "requests to the other host, with these device tokens: \(tokensElsewhere)")
        #expect(RedirectStub.requestedHosts == ["primary.test"])
        #expect(response?.status != 200)
    }

    /// A mirror's health check counts the redirect as a failed check, not the other host's answer.
    @Test
    func aHealthCheckFollowsNoRedirect() async throws {
        let target = try LoopbackServer(answerStart: Self.answer(#"{"data":{"status":"OK"}}"#))
        let targetURL = try await target.start()
        defer { target.stop() }
        let redirecting = try LoopbackServer(answerStart: Self.redirect(to: targetURL.appending(path: "health")))
        let redirectingURL = try await redirecting.start()
        defer { redirecting.stop() }

        let succeeded = await HealthCheck.succeeds(url: redirectingURL.appending(path: "health"), timeout: 5)

        #expect(!succeeded)
        #expect(target.requestCount == 0)
    }

    /// The mirror list is read only from the address asked.
    @Test
    func theMirrorListFollowsNoRedirect() async throws {
        let target = try LoopbackServer(answerStart: Self.answer(#"{"data":[{"type":"REGULAR","endpoint":"mirror.test"}]}"#))
        let targetURL = try await target.start()
        defer { target.stop() }
        let redirecting = try LoopbackServer(answerStart: Self.redirect(to: targetURL.appending(path: "mirrors")))
        let redirectingURL = try await redirecting.start()
        defer { redirecting.stop() }

        let mirrors = try? await MirrorsBootstrapService(urls: [redirectingURL.appending(path: "mirrors")], timeout: 5).fetch()

        #expect(mirrors == nil)
        #expect(target.requestCount == 0)
    }

    private static func answer(_ body: String) -> String {
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    }

    private static func redirect(to url: URL) -> String {
        "HTTP/1.1 302 Found\r\nLocation: \(url.absoluteString)\r\nContent-Length: 0\r\n\r\n"
    }
}

// MARK: - RedirectStub

/// Answers `primary.test` with a 302 to `elsewhere.test`, and `elsewhere.test` with 200, recording each request's host
/// and device token. `@unchecked` because URLProtocol is not Sendable; the serialized suite is the only writer.
private final class RedirectStub: URLProtocol, @unchecked Sendable {
    private struct Sent {
        let host: String
        let token: String?
    }

    private static let sent = Mutex<[Sent]>([])

    static func reset() {
        sent.withLock { $0 = [] }
    }

    static var requestedHosts: [String] {
        sent.withLock { $0.map(\.host) }
    }

    static func tokensSent(to host: String) -> [String?] {
        sent.withLock { $0.filter { $0.host == host }.map(\.token) }
    }

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        Self.sent.withLock { $0.append(Sent(host: host, token: request.value(forHTTPHeaderField: "x-device-token"))) }
        if host == "primary.test" {
            let elsewhere = URL(string: "https://elsewhere.test/steal")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": elsewhere.absoluteString])!
            var redirected = request
            redirected.url = elsewhere
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
