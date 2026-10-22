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
@Suite(.serialized, .timeLimit(.minutes(1)))
struct HTTPClientExecuteTests {
    struct Target: APITarget {
        var reportsDeviceState = true
        var method = HTTPMethod.get
        var payload = RequestPayload.none
        var path: String { "server" }
    }

    private struct Answer: Decodable, Equatable {
        let origin: String
    }

    private struct Storage: DeviceTokenProvider {
        var deviceToken: DeviceToken?
    }

    private let request = APIRequest(target: Target(), timeoutInterval: 5)

    /// `resolver`, when given, replaces the one built for `mirror`.
    private func makeClient(
        primary: URL = URL(string: "https://primary.test")!,
        mirror: MirrorResolver.Resolved?,
        resolver: MirrorResolver? = nil,
        token: String? = nil,
        isReachable: @escaping @Sendable () async -> Bool = { true },
        clock: any Clock<Duration> = ContinuousClock()
    ) async -> (DefaultHTTPClient, MirrorResolver) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        // No mirror list: only `mirror`, as if a resolution had found it, is ever tried.
        let resolver = resolver ?? MirrorResolver(bootstrap: MirrorsBootstrapService(urls: [], timeout: 1), resolved: mirror, probe: { _ in false })
        let transport = MirroredTransport(
            configuration: BackendConfiguration(
                backendURL: primary,
                deviceTokenProvider: Storage(deviceToken: token.map { DeviceToken(id: "token-id", token: $0) })
            ),
            sessionConfiguration: configuration,
            resolver: resolver,
            isReachable: isReachable,
            clock: clock
        )
        return (DefaultHTTPClient(transport: transport), resolver)
    }

    // MARK: Mirror fallback

    /// The limits: one no longer than the time a silent primary gets, and one with that time running.
    private static let limits: [TimeInterval] = [5, 60]

    @Test(arguments: limits)
    func aPrimaryTimeoutIsAnsweredByTheMirror(limit: TimeInterval) async throws {
        StubProtocol.answers = ["primary.test": .failure(URLError(.timedOut)), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"))

        let answer = try await client.execute(APIRequest(target: Target(), timeoutInterval: limit), as: Answer.self)

        #expect(answer == Answer(origin: "mirror"))
        #expect(await resolver.shouldPreferMirror())
    }

    @Test(arguments: limits)
    func aPrimaryServerErrorIsAnsweredByTheMirror(limit: TimeInterval) async throws {
        StubProtocol.answers = ["primary.test": .status(503), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"))

        #expect(try await client.execute(APIRequest(target: Target(), timeoutInterval: limit), as: Answer.self) == Answer(origin: "mirror"))
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

    /// A preference for a mirror with no mirror to be found leaves the request to the primary, and its failure is what
    /// the caller sees.
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

    // MARK: Silent primary

    /// A primary that never answers hands the request to the mirror within the request's limit, before the deadline
    /// cancels it: a GET goes to the mirror too, and a request with a body is cancelled on the primary first. The limit
    /// is long, so URLSession's own timeout, which runs in real time, never ends the primary's attempt during the test.
    @Test(arguments: [Target(), Target(method: .post, payload: .json(["name": "value"]))])
    func aSilentPrimaryHandsTheRequestToTheMirrorWithinItsLimit(target: Target) async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let clock = ManualClock()
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        let request = APIRequest(target: target, timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["primary.test"] }
        clock.advance(by: .seconds(59))
        // A request that was never handed over ends only at the deadline.
        if (try? await eventually { StubProtocol.requestedHosts.contains("mirror.test") }) == nil {
            clock.advance(by: .seconds(1))
        }

        #expect(StubProtocol.requestedHosts == ["primary.test", "mirror.test"])
        #expect(try await execution.value == Answer(origin: "mirror"))
        #expect(await resolver.shouldPreferMirror())
    }

    /// A GET whose primary answers first, after the mirror was asked too, ends with the primary's answer, and later
    /// requests stay with the primary.
    @Test
    func aPrimaryThatAnswersBeforeTheMirrorKeepsLaterRequests() async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .hang]
        let clock = ManualClock()
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        let request = APIRequest(target: Target(), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["primary.test"] }
        clock.advance(by: .seconds(59))
        try await eventually { StubProtocol.requestedHosts.contains("mirror.test") }
        try await StubProtocol.answerHanging(on: "primary.test", with: .json(#"{"origin":"primary"}"#))

        #expect(try await execution.value == Answer(origin: "primary"))
        #expect(await !resolver.shouldPreferMirror())
    }

    /// A silent primary with no mirror to take over keeps the request's whole limit, and its late answer counts.
    @Test
    func aSilentPrimaryWithoutAMirrorKeepsTheWholeLimit() async throws {
        StubProtocol.answers = ["primary.test": .hang]
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: nil, clock: clock)
        let request = APIRequest(target: Target(), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["primary.test"] }
        clock.advance(by: .seconds(59))
        try await StubProtocol.answerHanging(on: "primary.test", with: .json(#"{"origin":"primary"}"#))

        #expect(try await execution.value == Answer(origin: "primary"))
        #expect(StubProtocol.requestedHosts == ["primary.test"])
    }

    /// A request that shows nothing before its answer (no body, and not a GET) stays with a silent primary, which may be
    /// acting on it, and ends at its deadline.
    @Test
    func aRequestThePrimaryMayBeActingOnIsNeverHandedOver() async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        let request = APIRequest(target: Target(method: .post), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["primary.test"] }
        clock.advance(by: .seconds(59))
        // Time for a wrong handover to show.
        try await Task.sleep(for: .milliseconds(100))
        clock.advance(by: .seconds(1))

        await #expect(throws: APIError.unreachable(.timedOut)) { try await execution.value }
        #expect(StubProtocol.requestedHosts == ["primary.test"])
    }

    /// A primary that took the request's body may be acting on it: the request never goes to the mirror too, and ends
    /// as a timeout, whether the primary was seen to start in time or only after it was cancelled for the mirror. A body
    /// leaves only over a real connection, so the primary is a loopback server.
    @Test
    func aPrimaryThatTookTheBodyNeverHasTheRequestSentTwice() async throws {
        let server = try LoopbackServer()
        let primary = try await server.start()
        defer { server.stop() }
        StubProtocol.answers = ["mirror.test": .json(#"{"origin":"mirror"}"#)]
        let clock = ManualClock()
        let (client, _) = await makeClient(primary: primary, mirror: .regular(host: "mirror.test"), clock: clock)
        let request = APIRequest(target: Target(method: .post, payload: .json(["name": "value"])), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { server.requestCount == 1 }
        clock.advance(by: .seconds(59))
        // Time for a wrong handover to show.
        try await Task.sleep(for: .milliseconds(100))
        clock.advance(by: .seconds(1))

        await #expect(throws: APIError.unreachable(.timedOut)) { try await execution.value }
        #expect(StubProtocol.requestedHosts.isEmpty)
    }

    // MARK: Cancellation

    /// The primary, the mirror resolution and the mirror attempts share the request's timeout: a primary that answers
    /// 500 and a mirror that never answers end the request at its deadline, not one full timeout per attempt later,
    /// with the primary's answer, which says more than the mirror's silence.
    @Test
    func aSilentMirrorEndsTheRequestAtItsDeadlineWithThePrimaryAnswer() async throws {
        // The primary takes a while; the mirror's own wait used to start only then.
        StubProtocol.answers = ["primary.test": .after(0.1, .status(500)), "mirror.test": .hang]
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        let request = APIRequest(target: Target(), timeoutInterval: 1)

        let execution = Task {
            await #expect(throws: APIError.backend(status: 500, code: nil)) { try await client.execute(request, as: Answer.self) }
        }
        try await eventually { StubProtocol.requestedHosts.contains("mirror.test") }
        clock.advance(by: .seconds(1))
        await execution.value

        #expect(StubProtocol.requestedHosts == ["primary.test", "mirror.test"])
    }

    /// With no answer from the primary either, the deadline ends the request as a timeout.
    @Test
    func aSilentMirrorAfterASilentPrimaryEndsAsATimeout() async throws {
        StubProtocol.answers = ["primary.test": .after(0.1, .failure(URLError(.timedOut))), "mirror.test": .hang]
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        let request = APIRequest(target: Target(), timeoutInterval: 1)

        let execution = Task {
            await #expect(throws: APIError.unreachable(.timedOut)) { try await client.execute(request, as: Answer.self) }
        }
        try await eventually { StubProtocol.requestedHosts.contains("mirror.test") }
        clock.advance(by: .seconds(1))
        await execution.value
    }

    /// A request whose caller gave up (the app's limit on its IP lookup) is cancelled with it and fails with
    /// `CancellationError`: no fallback to the mirror, and no preference for it afterwards, also while the time a silent
    /// primary gets is running.
    @Test(arguments: limits)
    func aCancelledRequestNeitherFallsBackNorPrefersTheMirror(limit: TimeInterval) async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"))
        let task = Task { try await client.execute(APIRequest(target: Target(), timeoutInterval: limit), as: Answer.self) }
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

// MARK: - Silent preferred mirror

extension HTTPClientExecuteTests {
    /// A preferred mirror that never answers hands the request to the primary within the request's limit, as a silent
    /// primary hands it to a mirror: a GET goes to the primary too, and a request with a body is stopped on the mirror
    /// first. The primary's answer brings later requests back to it.
    @Test(arguments: [Target(), Target(method: .post, payload: .json(["name": "value"]))])
    func aSilentPreferredMirrorHandsTheRequestToThePrimaryWithinItsLimit(target: Target) async throws {
        StubProtocol.answers = ["primary.test": .json(#"{"origin":"primary"}"#), "mirror.test": .hang]
        let clock = ManualClock()
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        await resolver.mirrorAnswered()
        let request = APIRequest(target: target, timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["mirror.test"] }
        clock.advance(by: .seconds(59))
        // A request that was never handed over ends only at the deadline.
        if (try? await eventually { StubProtocol.requestedHosts.contains("primary.test") }) == nil {
            clock.advance(by: .seconds(1))
        }

        #expect(StubProtocol.requestedHosts == ["mirror.test", "primary.test"])
        #expect(try await execution.value == Answer(origin: "primary"))
        #expect(await !resolver.shouldPreferMirror())
        // A body leaves the mirror before the primary has it; a GET's mirror still runs as the primary is asked.
        let order = target.method == .get ? ["mirror.test", "primary.test"] : ["mirror.test", "stop mirror.test", "primary.test"]
        #expect(Array(StubProtocol.journal.prefix(order.count)) == order)
    }

    /// A preferred mirror still being looked up, its probes never ending, gives the request to the primary in the same
    /// way.
    @Test(arguments: [Target(), Target(method: .post, payload: .json(["name": "value"]))])
    func aPreferredMirrorStillLookedUpHandsTheRequestToThePrimary(target: Target) async throws {
        StubProtocol.answers = ["primary.test": .json(#"{"origin":"primary"}"#), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let lookup = SlowLookup()
        let resolver = await lookup.resolver()
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: nil, resolver: resolver, clock: clock)
        let request = APIRequest(target: target, timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { lookup.hasStarted }
        clock.advance(by: .seconds(59))
        if (try? await eventually { StubProtocol.requestedHosts.contains("primary.test") }) == nil {
            clock.advance(by: .seconds(1))
        }

        #expect(try await execution.value == Answer(origin: "primary"))
        #expect(StubProtocol.requestedHosts == ["primary.test"])
        #expect(await !resolver.shouldPreferMirror())
    }

    /// A GET whose mirror answers first, after the primary was asked too, ends with the mirror's answer, and later
    /// requests stay with the mirror.
    @Test
    func aMirrorThatAnswersBeforeThePrimaryKeepsThePreference() async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .hang]
        let clock = ManualClock()
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        await resolver.mirrorAnswered()
        let request = APIRequest(target: Target(), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["mirror.test"] }
        clock.advance(by: .seconds(59))
        try await eventually { StubProtocol.requestedHosts.contains("primary.test") }
        try await StubProtocol.answerHanging(on: "mirror.test", with: .json(#"{"origin":"mirror"}"#))

        #expect(try await execution.value == Answer(origin: "mirror"))
        #expect(await resolver.shouldPreferMirror())
    }

    /// A request that shows nothing before its answer (no body, and not a GET) stays with a silent preferred mirror,
    /// which may be acting on it, and ends at its deadline.
    @Test
    func aRequestThePreferredMirrorMayBeActingOnStaysWithIt() async throws {
        StubProtocol.answers = ["primary.test": .json(#"{"origin":"primary"}"#), "mirror.test": .hang]
        let clock = ManualClock()
        let (client, resolver) = await makeClient(mirror: .regular(host: "mirror.test"), clock: clock)
        await resolver.mirrorAnswered()
        let request = APIRequest(target: Target(method: .post), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { StubProtocol.requestedHosts == ["mirror.test"] }
        clock.advance(by: .seconds(59))
        // Time for a wrong handover to show, once the silence is over and only the deadline sleeps.
        try await eventually { clock.sleepers == 1 }
        try await Task.sleep(for: .milliseconds(100))
        clock.advance(by: .seconds(1))

        await #expect(throws: APIError.unreachable(.timedOut)) { try await execution.value }
        #expect(StubProtocol.requestedHosts == ["mirror.test"])
    }

    /// A preferred mirror that took the request's body may be acting on it: the request never goes to the primary too,
    /// and ends as a timeout. A body leaves only over a real connection, so the mirror is a loopback server, which the
    /// primary's address reaches with the mirror's host on the same port.
    @Test
    func aMirrorThatTookTheBodyNeverHasTheRequestSentTwice() async throws {
        let server = try LoopbackServer()
        let loopback = try await server.start()
        defer { server.stop() }
        StubProtocol.answers = ["primary.test": .json(#"{"origin":"primary"}"#)]
        let clock = ManualClock()
        let primary = try #require(URL(string: "http://primary.test:\(loopback.port ?? 0)"))
        let (client, resolver) = await makeClient(primary: primary, mirror: .regular(host: LoopbackServer.host), clock: clock)
        await resolver.mirrorAnswered()
        let request = APIRequest(target: Target(method: .post, payload: .json(["name": "value"])), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { server.requestCount == 1 }
        clock.advance(by: .seconds(59))
        // Time for a wrong handover to show, once the silence is over and only the deadline sleeps.
        try await eventually { clock.sleepers == 1 }
        try await Task.sleep(for: .milliseconds(100))
        clock.advance(by: .seconds(1))

        await #expect(throws: APIError.unreachable(.timedOut)) { try await execution.value }
        #expect(StubProtocol.requestedHosts.isEmpty)
    }

    /// A request with a body handed to the primary while its mirror was still being looked up goes to the mirror found
    /// later if the primary fails before taking it: the mirror never had it.
    @Test
    func aBodyThePrimaryFailedToTakeGoesToAMirrorFoundLater() async throws {
        StubProtocol.answers = ["primary.test": .failure(URLError(.cannotConnectToHost)), "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let lookup = SlowLookup()
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: nil, resolver: lookup.resolver(), clock: clock)
        let request = APIRequest(target: Target(method: .post, payload: .json(["name": "value"])), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { lookup.hasStarted }
        clock.advance(by: .seconds(59))
        try await eventually { StubProtocol.requestedHosts == ["primary.test"] }
        lookup.find()

        #expect(try await execution.value == Answer(origin: "mirror"))
        #expect(StubProtocol.requestedHosts == ["primary.test", "mirror.test"])
    }

    /// A mirror found while the primary has the request's body waits: the request goes to one endpoint at a time, and
    /// the primary's answer ends it.
    @Test
    func aMirrorFoundWhileThePrimaryHasTheBodyWaits() async throws {
        StubProtocol.answers = ["primary.test": .hang, "mirror.test": .json(#"{"origin":"mirror"}"#)]
        let lookup = SlowLookup()
        let clock = ManualClock()
        let (client, _) = await makeClient(mirror: nil, resolver: lookup.resolver(), clock: clock)
        let request = APIRequest(target: Target(method: .post, payload: .json(["name": "value"])), timeoutInterval: 60)

        let execution = Task { try await client.execute(request, as: Answer.self) }
        try await eventually { lookup.hasStarted }
        clock.advance(by: .seconds(59))
        try await eventually { StubProtocol.requestedHosts == ["primary.test"] }
        lookup.find()
        // Time for a wrong send to the mirror to show.
        try await Task.sleep(for: .milliseconds(100))
        try await StubProtocol.answerHanging(on: "primary.test", with: .json(#"{"origin":"primary"}"#))

        #expect(try await execution.value == Answer(origin: "primary"))
        #expect(StubProtocol.requestedHosts == ["primary.test"])
    }
}

/// A preferred mirror's lookup that lasts until the test lets it find `mirror.test`: the search's own 30 s run on the
/// real clock, so only the request's time passes in a test.
private final class SlowLookup: Sendable {
    private let started = Mutex(false)
    private let found = AsyncStream.makeStream(of: Void.self)

    var hasStarted: Bool { started.withLock { $0 } }

    /// A resolver that prefers a mirror and looks it up here.
    func resolver() async -> MirrorResolver {
        let resolver = MirrorResolver(
            bootstrap: MirrorsBootstrapService(urls: [], timeout: 1),
            mirrors: [Mirror(type: .regular, endpoint: "mirror.test", availableSniOptions: nil)]
        ) { _ in await self.probe() }
        await resolver.mirrorAnswered()
        return resolver
    }

    func find() {
        found.continuation.yield()
    }

    private func probe() async -> Bool {
        started.withLock { $0 = true }
        for await _ in found.stream {
            return true
        }
        return false
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

/// Answers every request from `answers`, keyed by host, and records the hosts asked; a loopback server's requests go to
/// it. `@unchecked` because URLProtocol is not Sendable; the serialized suite is the only writer.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    indirect enum Answer: Sendable {
        case json(String)
        /// A status with `body`, such as the backend's `{"error": …}`.
        case status(Int, body: String = "{}")
        case failure(URLError)
        /// No answer at all, until the request is cancelled or `answerHanging(on:with:)` answers it.
        case hang
        /// `answer`, `seconds` after the request was sent.
        case after(TimeInterval, Answer)
    }

    nonisolated(unsafe) static var answers: [String: Answer] = [:] {
        didSet {
            requestedHosts = []
            events.withLock { $0 = [] }
            hangingLock.withLock { hanging = [] }
        }
    }

    private static let hosts = Mutex<[String]>([])
    static var requestedHosts: [String] {
        get { hosts.withLock { $0 } }
        set { hosts.withLock { $0 = newValue } }
    }

    /// The requests' starts and ends in order: a host as it is asked, "stop" and the host as its request ends.
    private static let events = Mutex<[String]>([])
    static var journal: [String] { events.withLock { $0 } }

    /// A request left hanging: its stub, its host, and a way to answer it. Kept under a lock, and without the stub itself,
    /// which the compiler lets neither into a `Mutex` nor be answered from a static method.
    private struct Hanging {
        let stub: ObjectIdentifier
        let host: String?
        let answer: @Sendable (Answer) -> Void
    }

    private static let hangingLock = NSLock()
    private nonisolated(unsafe) static var hanging: [Hanging] = []

    /// Answers the requests to `host` left hanging with `answer`, once there is one: a request's host is recorded a
    /// moment before it hangs.
    static func answerHanging(on host: String, with answer: Answer) async throws {
        try await eventually { hangingLock.withLock { hanging.contains { $0.host == host } } }
        let requests = hangingLock.withLock {
            defer { hanging.removeAll { $0.host == host } }
            return hanging.filter { $0.host == host }
        }
        for request in requests {
            request.answer(answer)
        }
    }

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host != LoopbackServer.host }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // A request cancelled as it was sent, perhaps in the test before, still reaches here, already completed.
        guard task?.state == .running else { return }
        let host = request.url?.host ?? ""
        Self.hosts.withLock { $0.append(host) }
        Self.events.withLock { $0.append(host) }
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
            Self.hangingLock.withLock {
                Self.hanging.append(Hanging(stub: ObjectIdentifier(self), host: url.host) { self.deliver($0, for: url) })
            }
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

    override func stopLoading() {
        Self.hangingLock.withLock { Self.hanging.removeAll { $0.stub == ObjectIdentifier(self) } }
        let host = request.url?.host ?? ""
        Self.events.withLock { $0.append("stop \(host)") }
    }
}
