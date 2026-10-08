//
//  HTTPClientExecuteTests.swift
//  DVPNSDK
//

import Dependencies
@testable import DVPNSDK
import Foundation
import Synchronization
import Testing

/// `DefaultHTTPClient.execute` over `MirroredTransport` and a stubbed session, end to end: the mirror fallback, the
/// errors and the device events. The stub answers by host, so the suite runs serially.
@Suite(.serialized)
struct HTTPClientExecuteTests {
    private struct Target: APITarget {
        var reportsDeviceState = true
        var method: HTTPMethod { .get }
        var path: String { "server" }
        var payload: RequestPayload { .none }
    }

    private struct Answer: Decodable, Equatable {
        let origin: String
    }

    private struct Storage: DeviceTokenProvider {
        var deviceToken: DeviceToken?
    }

    private let primary = URL(string: "https://primary.test")!
    private let request = APIRequest(target: Target(), timeoutInterval: 5)

    private func makeClient(
        mirror: MirrorResolver.Resolved?,
        token: String? = nil,
        isReachable: @escaping @Sendable () async -> Bool = { true }
    ) async -> (DefaultHTTPClient, MirrorResolver) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        // No mirror list: only `mirror`, as if a resolution had found it, is ever tried.
        let resolver = MirrorResolver(bootstrap: MirrorsBootstrapService(urls: [], timeout: 1), resolved: mirror, probe: { _ in false })
        let transport = MirroredTransport(
            configuration: BackendConfiguration(
                backendURL: primary,
                deviceTokenProvider: Storage(deviceToken: token.map { DeviceToken(id: "token-id", token: $0) })
            ),
            sessionConfiguration: configuration,
            resolver: resolver,
            isReachable: isReachable
        )
        return (DefaultHTTPClient(transport: transport), resolver)
    }

    // MARK: Mirror fallback

    @Test
    func aPrimaryTimeoutIsAnsweredByTheMirror() async throws {
        StubProtocol.answers = ["primary.test": .failure(URLError(.timedOut)), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"))

        let answer = try await client.execute(request, as: Answer.self)

        #expect(answer == Answer(origin: "mirror"))
        #expect(await resolver.shouldPreferMirror())
    }

    @Test
    func aPrimaryServerErrorIsAnsweredByTheMirror() async throws {
        StubProtocol.answers = ["primary.test": .status(503), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"))

        #expect(try await client.execute(request, as: Answer.self) == Answer(origin: "mirror"))
    }

    @Test
    func aClientErrorIsNotRetriedOnAMirror() async {
        StubProtocol.answers = ["primary.test": .status(400), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"))

        await #expect(throws: APIError.backend(status: 400, code: nil)) { try await client.execute(request, as: Answer.self) }
        #expect(StubProtocol.requestedHosts == ["primary.test"])
        #expect(await !resolver.shouldPreferMirror())
    }

    /// Without a mirror the caller sees the primary's failure, not "no healthy mirror", and the next request
    /// tries the primary again.
    @Test
    func withoutAMirrorThePrimaryFailureIsThrown() async {
        StubProtocol.answers = ["primary.test": .failure(URLError(.timedOut))]
        let (client, resolver) = await makeClient(mirror: nil)

        await #expect(throws: APIError.unreachable(.timedOut)) {
            try await client.execute(request, as: Answer.self)
        }
        #expect(await !resolver.shouldPreferMirror())
    }

    /// A primary that cannot be found or reached by name or address, with no mirror to take over, fails as offline,
    /// as a timeout does.
    @Test(arguments: [URLError.Code.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed])
    func aPrimaryThatCannotBeReachedFailsAsOffline(code: URLError.Code) async {
        StubProtocol.answers = ["primary.test": .failure(URLError(code))]
        let (client, _) = await makeClient(mirror: nil)

        await #expect(throws: APIError.unreachable(code)) { try await client.execute(request, as: Answer.self) }
        #expect(APIError.unreachable(code).reason == .noConnection)
    }

    /// A preferred mirror that stops answering, with no other to take over, leaves the request to the primary
    /// instead of failing with `MirrorError`.
    @Test
    func aPreferredMirrorThatStopsAnsweringLeavesTheRequestToThePrimary() async throws {
        StubProtocol.answers = ["primary.test": .failure(URLError(.timedOut)), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"))
        _ = try await client.execute(request, as: Answer.self)

        StubProtocol.answers = ["primary.test": .json(#"{"origin":"primary"}"#), "mirror.test": .failure(URLError(.timedOut))]

        #expect(try await client.execute(request, as: Answer.self) == Answer(origin: "primary"))
        #expect(await !resolver.shouldPreferMirror())
    }

    /// `refreshEndpoint` prefers a mirror when the primary's ping fails, also when no mirror can be found. The
    /// requests still reach the primary, and its failure is what the caller sees.
    @Test
    func aPreferredMirrorThatCannotBeFoundThrowsThePrimaryFailure() async {
        StubProtocol.answers = ["primary.test": .failure(URLError(.timedOut))]
        let (client, resolver) = await makeClient(mirror: nil)
        await resolver.mirrorAnswered()

        await #expect(throws: APIError.unreachable(.timedOut)) {
            try await client.execute(request, as: Answer.self)
        }
        #expect(StubProtocol.requestedHosts == ["primary.test"])
    }

    // MARK: Cancellation

    /// The primary, the mirror resolution and the mirror attempts share the request's timeout: a primary that answers
    /// 500 and a mirror that never answers end the request at its deadline, not one full timeout per attempt later,
    /// with the primary's answer, which says more than the mirror's silence.
    @Test
    func aSilentMirrorEndsTheRequestAtItsDeadlineWithThePrimaryAnswer() async {
        // The primary takes most of the request's second; the mirror's own wait used to start only then.
        StubProtocol.answers = ["primary.test": .after(0.8, .status(500)), "mirror.test": .hang]
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"))
        let request = APIRequest(target: Target(), timeoutInterval: 1)
        let start = ContinuousClock.now

        await #expect(throws: APIError.backend(status: 500, code: nil)) { try await client.execute(request, as: Answer.self) }

        #expect(ContinuousClock.now - start < .milliseconds(1_400))
        #expect(StubProtocol.requestedHosts == ["primary.test", "mirror.test"])
    }

    /// With no answer from the primary either, the deadline ends the request as a timeout.
    @Test
    func aSilentMirrorAfterASilentPrimaryEndsAsATimeout() async {
        StubProtocol.answers = ["primary.test": .after(0.8, .failure(URLError(.timedOut))), "mirror.test": .hang]
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"))
        let request = APIRequest(target: Target(), timeoutInterval: 1)
        let start = ContinuousClock.now

        await #expect(throws: APIError.unreachable(.timedOut)) { try await client.execute(request, as: Answer.self) }

        #expect(ContinuousClock.now - start < .milliseconds(1_400))
    }

    /// A request whose caller gave up (the app's limit on its IP lookup) is cancelled with it and fails with
    /// `CancellationError`: no fallback to the mirror, and no preference for it afterwards.
    @Test
    func aCancelledRequestNeitherFallsBackNorPrefersTheMirror() async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"))
        let task = Task { try await client.execute(request, as: Answer.self) }
        try await Task.sleep(for: .milliseconds(100))

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(StubProtocol.requestedHosts == ["primary.test"])
        #expect(await !resolver.shouldPreferMirror())
    }

    /// An endpoint check cut short says nothing about the primary: it does not switch requests to a mirror. The ping
    /// reads the configuration, which is set here: resolving its default inside a test crashes Swift Testing.
    @Test
    func aCancelledEndpointCheckLeavesTheResolverAlone() async {
        StubProtocol.answers = [:]
        await withDependencies {
            $0.backendConfiguration = BackendConfiguration(backendURL: URL(string: "https://primary.test")!)
        } operation: {
            let (client, resolver) = await makeClient(mirror: nil)
            let task = Task { await client.refreshEndpoint() }

            task.cancel()
            await task.value

            #expect(await !resolver.shouldPreferMirror())
        }
    }

    // MARK: Reachability

    /// With no network path a request fails at once as offline: nothing is sent and no mirror is tried or preferred,
    /// when the path's status is known.
    @Test
    func withoutANetworkARequestFailsAtOnceAsOffline() async {
        StubProtocol.answers = ["primary.test": .json(#"{"origin":"primary"}"#)]
        let (client, resolver) = await makeClient(mirror: nil, isReachable: { false })

        await #expect(throws: APIError.offline) { try await client.execute(request, as: Answer.self) }

        #expect(StubProtocol.requestedHosts.isEmpty)
        #expect(await !resolver.shouldPreferMirror())
    }

    /// The endpoint check neither pings the primary nor prefers a mirror because of a missing network.
    @Test
    func withoutANetworkTheEndpointCheckLeavesTheResolverAlone() async {
        StubProtocol.answers = [:]
        let (client, resolver) = await makeClient(mirror: nil, isReachable: { false })

        await client.refreshEndpoint()

        #expect(StubProtocol.requestedHosts.isEmpty)
        #expect(await !resolver.shouldPreferMirror())
    }

    // MARK: Device events

    @Test
    func aDeviceStateIsPublishedWithTheTokenTheRequestCarried() async {
        StubProtocol.answers = ["primary.test": .status(401)]
        let (client, _) = await makeClient(mirror: nil, token: "token-a")
        let events = client.deviceEvents()

        await #expect(throws: APIError.backend(status: 401, code: nil)) { try await client.execute(request, as: Answer.self) }
        #expect(await firstEvent(of: events) == DeviceEvent(state: .unauthorized, sentToken: "token-a"))
    }

    /// The backend's own error bodies: the code, not only the status, decides what is published.
    @Test(arguments: [
        (401, "unauthorizedDevice", DeviceState.unauthorized),
        (403, "bannedDevice", .banned),
        (403, "appInactive", .appInactive),
        (425, "deviceNotEnrolled", .notEnrolled),
    ])
    func aBackendErrorPublishesItsDeviceState(status: Int, code: String, expected: DeviceState) async {
        StubProtocol.answers = ["primary.test": .status(status, body: #"{"error":"\#(code)","reason":""}"#)]
        let (client, _) = await makeClient(mirror: nil, token: "token-b")
        let events = client.deviceEvents()

        await #expect(throws: APIError.backend(status: status, code: code)) { try await client.execute(request, as: Answer.self) }
        #expect(await firstEvent(of: events) == DeviceEvent(state: expected, sentToken: "token-b"))
    }

    /// A 401 with a code the SDK does not know describes something other than the device (another API's refusal), so
    /// it must not make the app register a new one.
    @Test
    func aRefusalWithAnUnknownCodePublishesNothing() async {
        StubProtocol.answers = ["primary.test": .status(401, body: #"{"error":"somethingElse","reason":""}"#)]
        let (client, _) = await makeClient(mirror: nil, token: "token-c")
        let events = client.deviceEvents()

        await #expect(throws: APIError.backend(status: 401, code: "somethingElse")) { try await client.execute(request, as: Answer.self) }
        #expect(await firstEvent(of: events) == nil)
    }

    @Test
    func aTargetThatDoesNotReportTheDevicePublishesNothing() async {
        StubProtocol.answers = ["primary.test": .status(401)]
        let (client, _) = await makeClient(mirror: nil, token: "token-a")
        let events = client.deviceEvents()
        let signIn = APIRequest(target: Target(reportsDeviceState: false))

        await #expect(throws: APIError.backend(status: 401, code: nil)) { try await client.execute(signIn, as: Answer.self) }
        #expect(await firstEvent(of: events) == nil)
    }

    /// Every subscriber gets the event.
    @Test
    func everySubscriberGetsTheEvent() async {
        StubProtocol.answers = ["primary.test": .status(403)]
        let (client, _) = await makeClient(mirror: nil)
        let first = client.deviceEvents()
        let second = client.deviceEvents()

        await #expect(throws: APIError.backend(status: 403, code: nil)) { try await client.execute(request, as: Answer.self) }
        #expect(await firstEvent(of: first) == DeviceEvent(state: .banned, sentToken: nil))
        #expect(await firstEvent(of: second) == DeviceEvent(state: .banned, sentToken: nil))
    }
}

/// The first event `events` holds, or nil when none comes within `limit`. `execute` publishes before it throws, so an
/// event that was published is there at once.
private func firstEvent(of events: AsyncStream<DeviceEvent>, within limit: Duration = .milliseconds(200)) async -> DeviceEvent? {
    await withTaskGroup(of: DeviceEvent?.self) { group in
        group.addTask {
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: limit)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: - Stub

/// Answers every request from `answers`, keyed by host, and records the hosts asked.
/// `@unchecked` because URLProtocol is not Sendable; the serialized suite is the only writer.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    indirect enum Answer: Sendable {
        case json(String)
        /// A status with `body`, such as the backend's `{"error": …}`.
        case status(Int, body: String = "{}")
        case failure(URLError)
        /// No answer at all, until the request is cancelled.
        case hang
        /// `answer`, `seconds` after the request was sent.
        case after(TimeInterval, Answer)
    }

    nonisolated(unsafe) static var answers: [String: Answer] = [:] {
        didSet { requestedHosts = [] }
    }

    nonisolated(unsafe) static var requestedHosts: [String] = []

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.requestedHosts.append(host)
        guard let url = request.url, let answer = Self.answers[host] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        deliver(answer, for: url)
    }

    private func deliver(_ answer: Answer, for url: URL) {
        switch answer {
        case let .after(seconds, answer):
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                self.deliver(answer, for: url)
            }
        case .hang:
            break
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .status(code, body):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .json(body):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
