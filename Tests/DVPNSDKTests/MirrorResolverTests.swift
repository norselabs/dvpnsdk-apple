@testable import DVPNSDK
import Foundation
import Synchronization
import Testing

// MARK: - Mirror Model Decoding

struct MirrorModelTests {
    @Test
    func decodeMirrorTypeRegular() throws {
        let json = Data("""
        {"type":"REGULAR","endpoint":"mirror1.example.com"}
        """.utf8)

        let decoder = JSONDecoder()
        let mirror = try decoder.decode(Mirror.self, from: json)

        #expect(mirror.type == .regular)
        #expect(mirror.endpoint == "mirror1.example.com")
        #expect(mirror.availableSniOptions == nil)
    }

    @Test
    func decodeMirrorTypeSNISpoof() throws {
        let json = Data("""
        {
            "type": "SNI_SPOOF",
            "endpoint": "1.2.3.4",
            "available_sni_options": ["google.com", "bing.com"]
        }
        """.utf8)

        let decoder = JSONDecoder()
        let mirror = try decoder.decode(Mirror.self, from: json)

        #expect(mirror.type == .sniSpoof)
        #expect(mirror.endpoint == "1.2.3.4")
        #expect(mirror.availableSniOptions == ["google.com", "bing.com"])
    }

    /// The bootstrap endpoints wrap the list in the API's `data` envelope; this is the exact
    /// shape `MirrorsBootstrapService.fetch()` decodes.
    @Test
    func decodeMirrorsResponse() throws {
        let json = Data("""
        {
            "data": [
                {"type": "REGULAR", "endpoint": "m1.example.com"},
                {"type": "SNI_SPOOF", "endpoint": "5.6.7.8", "available_sni_options": ["a.com"]}
            ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(DataResponse<[Mirror]>.self, from: json)

        #expect(response.data.count == 2)
        #expect(response.data[0].type == .regular)
        #expect(response.data[1].type == .sniSpoof)
        #expect(response.data[1].availableSniOptions?.first == "a.com")
    }

    @Test
    func decodeHealthResponseOK() throws {
        let json = Data("{\"data\":{\"status\":\"OK\"}}".utf8)

        let response = try JSONDecoder().decode(HealthResponse.self, from: json)

        #expect(response.data.status == "OK")
    }

    @Test
    func decodeHealthResponseDown() throws {
        let json = Data("{\"data\":{\"status\":\"DOWN\"}}".utf8)

        let response = try JSONDecoder().decode(HealthResponse.self, from: json)

        #expect(response.data.status != "OK")
    }

    @Test
    func decodeEmptyMirrorsList() throws {
        let json = Data("{\"data\":[]}".utf8)

        let response = try JSONDecoder().decode(DataResponse<[Mirror]>.self, from: json)

        #expect(response.data.isEmpty)
    }
}

// MARK: - MirrorResolver

struct MirrorResolverTests {
    private let noList = MirrorsBootstrapService(urls: [], timeout: 1)

    private static func regular(_ host: String) -> Mirror {
        Mirror(type: .regular, endpoint: host, availableSniOptions: nil)
    }

    private static func sni(_ ip: String, _ names: [String]) -> Mirror {
        Mirror(type: .sniSpoof, endpoint: ip, availableSniOptions: names)
    }

    @Test
    func resolvedEquality() {
        #expect(MirrorResolver.Resolved.regular(host: "a.com") == .regular(host: "a.com"))
        #expect(MirrorResolver.Resolved.regular(host: "a.com") != .regular(host: "b.com"))
        #expect(MirrorResolver.Resolved.sniSpoof(ip: "1.2.3.4", sni: "a.com") != .sniSpoof(ip: "1.2.3.4", sni: "b.com"))
    }

    /// A regular mirror is one route; an SNI mirror is one route per name, in the list's order.
    @Test
    func aMirrorsRoutes() {
        #expect(MirrorResolver.routes(of: Self.regular("m.test")) == [.regular(host: "m.test")])
        #expect(MirrorResolver.routes(of: Self.sni("192.0.2.1", ["a.test", "b.test"])) == [
            .sniSpoof(ip: "192.0.2.1", sni: "a.test"), .sniSpoof(ip: "192.0.2.1", sni: "b.test"),
        ])
    }

    @Test
    func withoutAMirrorListThereIsNoMirror() async {
        let resolver = MirrorResolver(bootstrap: noList, probe: { _ in true })
        await #expect(throws: MirrorError.bootstrapFailed) { try await resolver.currentMirror() }
        #expect(await resolver.refresh() == nil)
    }

    /// The mirrors are probed in parallel: a slow first mirror does not hold up a healthy second one.
    @Test
    func theFirstHealthyMirrorToAnswerWins() async throws {
        let resolver = MirrorResolver(bootstrap: noList, mirrors: [Self.regular("slow.test"), Self.regular("fast.test")]) { route in
            if route == .regular(host: "slow.test") { try? await Task.sleep(for: .seconds(5)) }
            return true
        }

        let start = ContinuousClock.now
        let found = try await resolver.currentMirror()

        #expect(found == .regular(host: "fast.test"))
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    /// An SNI mirror's names are tried one after another, the next after a failed one.
    @Test
    func anSNIMirrorsNamesAreTriedInTurn() async throws {
        let probed = Mutex<[MirrorResolver.Resolved]>([])
        let resolver = MirrorResolver(bootstrap: noList, mirrors: [Self.sni("192.0.2.1", ["a.test", "b.test", "c.test"])]) { route in
            probed.withLock { $0.append(route) }
            return route == .sniSpoof(ip: "192.0.2.1", sni: "b.test")
        }

        #expect(try await resolver.currentMirror() == .sniSpoof(ip: "192.0.2.1", sni: "b.test"))
        #expect(probed.withLock { $0 } == [.sniSpoof(ip: "192.0.2.1", sni: "a.test"), .sniSpoof(ip: "192.0.2.1", sni: "b.test")])
    }

    /// A resolution gives up once its budget is spent, whatever is still probing.
    @Test
    func aResolutionGivesUpWhenItsBudgetIsSpent() async {
        let resolver = MirrorResolver(bootstrap: noList, budget: .milliseconds(200), mirrors: [Self.regular("hangs.test")]) { _ in
            try? await Task.sleep(for: .seconds(10))
            return true
        }

        let elapsed = await ContinuousClock().measure {
            await #expect(throws: MirrorError.noHealthyMirror) { try await resolver.currentMirror() }
        }
        #expect(elapsed < .seconds(2))
    }

    /// A route that failed is skipped while another route answers.
    @Test
    func aFailedRouteIsSkippedWhileAnotherAnswers() async throws {
        let probed = Mutex<[MirrorResolver.Resolved]>([])
        let resolver = MirrorResolver(bootstrap: noList, mirrors: [Self.regular("a.test"), Self.regular("b.test")]) { route in
            probed.withLock { $0.append(route) }
            return true
        }

        await resolver.invalidate(.regular(host: "a.test"))
        #expect(try await resolver.currentMirror() == .regular(host: "b.test"))
        #expect(probed.withLock { $0 } == [.regular(host: "b.test")])
    }

    /// Once every route has failed, the next resolution probes them again rather than finding no mirror until the
    /// next refresh: a mirror that was down, or a network that let nothing through, may be back.
    @Test
    func routesThatAllFailedAreProbedAgainByTheNextResolution() async throws {
        let probed = Mutex(0)
        let healthy = Mutex(false)
        let resolver = MirrorResolver(bootstrap: noList, mirrors: [Self.regular("m.test")]) { _ in
            probed.withLock { $0 += 1 }
            return healthy.withLock { $0 }
        }

        await #expect(throws: MirrorError.noHealthyMirror) { try await resolver.currentMirror() }
        healthy.withLock { $0 = true }
        #expect(try await resolver.currentMirror() == .regular(host: "m.test"))
        #expect(probed.withLock { $0 } == 2)
    }

    /// The second pass is the only one: with nothing healthy, a resolution probes each route once (the routes that
    /// just failed are not probed again) and ends with no mirror.
    @Test
    func aResolutionProbesEachRouteOnceAndEnds() async {
        let probed = Mutex<[MirrorResolver.Resolved: Int]>([:])
        let resolver = MirrorResolver(
            bootstrap: noList,
            mirrors: [Self.regular("a.test"), Self.regular("b.test"), Self.sni("192.0.2.1", ["x.test", "y.test"])]
        ) { route in
            probed.withLock { $0[route, default: 0] += 1 }
            return false
        }

        await resolver.invalidate(.regular(host: "a.test"))
        await resolver.invalidate(.sniSpoof(ip: "192.0.2.1", sni: "y.test"))
        await #expect(throws: MirrorError.noHealthyMirror) { try await resolver.currentMirror() }
        #expect(probed.withLock { $0 } == [
            .regular(host: "a.test"): 1, .regular(host: "b.test"): 1,
            .sniSpoof(ip: "192.0.2.1", sni: "x.test"): 1, .sniSpoof(ip: "192.0.2.1", sni: "y.test"): 1,
        ])

        // The next resolution does the same, once each again: nothing repeats within one.
        await #expect(throws: MirrorError.noHealthyMirror) { try await resolver.currentMirror() }
        #expect(probed.withLock { $0.values.allSatisfy { $0 == 2 } })
    }

    /// The second pass shares the resolution's budget: when the first spent it, the skipped routes wait for the next
    /// resolution.
    @Test
    func theSecondPassKeepsToTheBudget() async {
        let probed = Mutex<[MirrorResolver.Resolved]>([])
        let resolver = MirrorResolver(
            bootstrap: noList,
            budget: .milliseconds(200),
            mirrors: [Self.regular("a.test"), Self.regular("hangs.test")]
        ) { route in
            probed.withLock { $0.append(route) }
            try? await Task.sleep(for: .seconds(10))
            return true
        }

        await resolver.invalidate(.regular(host: "a.test"))
        let elapsed = await ContinuousClock().measure {
            await #expect(throws: MirrorError.noHealthyMirror) { try await resolver.currentMirror() }
        }
        #expect(elapsed < .seconds(2))
        #expect(probed.withLock { $0 } == [.regular(host: "hangs.test")])
    }

    /// A request that failed hard on the resolved mirror drops it, and the next resolution skips it.
    @Test
    func anInvalidatedMirrorIsSkipped() async throws {
        let resolver = MirrorResolver(
            bootstrap: noList,
            mirrors: [Self.regular("a.test"), Self.regular("b.test")],
            resolved: .regular(host: "a.test")
        ) { route in
            if route == .regular(host: "a.test") { try? await Task.sleep(for: .milliseconds(100)) }
            return true
        }

        #expect(try await resolver.currentMirror() == .regular(host: "a.test"))
        await resolver.invalidate(.regular(host: "a.test"))
        // The list goes with the dropped mirror; the test gives no bootstrap URL, so this resolution has no list.
        await #expect(throws: MirrorError.bootstrapFailed) { try await resolver.currentMirror() }
    }

    /// What the transport reports moves the preference: a mirror that answered for a failed primary is preferred, no
    /// mirror answering returns to the primary, and a healthy primary forgets every mirror.
    @Test
    func theTransportsReportsMoveThePreference() async {
        let resolver = MirrorResolver(bootstrap: noList, probe: { _ in true })
        await resolver.mirrorAnswered()
        #expect(await resolver.shouldPreferMirror())
        await resolver.noMirrorAnswered()
        #expect(await !resolver.shouldPreferMirror())
        await resolver.primaryIsDown()
        #expect(await resolver.shouldPreferMirror())
        await resolver.primaryIsHealthy()
        #expect(await !resolver.shouldPreferMirror())
    }
}

// MARK: - Mirror-list sources

/// The SDK knows no address of its own: the backend's own `/mirrors` first, then the copies the app names.
struct BootstrapURLsTests {
    @Test
    func theBackendsOwnListComesFirstThenTheAppsCopies() throws {
        let backend = try #require(URL(string: "https://api.example.test"))
        let copy = try #require(URL(string: "https://storage.example.test/mirrors.json"))
        let configuration = BackendConfiguration(backendURL: backend, mirrorListURLs: [copy])

        #expect(configuration.bootstrapMirrorURLs == [backend.appendingPathComponent("mirrors"), copy])
    }

    @Test
    func withoutCopiesOnlyTheBackendsOwnListIsAsked() throws {
        let backend = try #require(URL(string: "https://api.example.test"))
        #expect(BackendConfiguration(backendURL: backend).bootstrapMirrorURLs == [backend.appendingPathComponent("mirrors")])
    }
}

// MARK: - Cancellation

/// A resolution whose caller gave up stops probing instead of trying every mirror and SNI option, 5 s each: the app's
/// limit on its IP lookup ends the work, not only the wait. The mirrors are TEST-NET addresses
/// that answer nothing, probed for real.
struct MirrorResolverCancellationTests {
    @Test
    func aCancelledResolutionStopsProbing() async throws {
        let mirrors = (1 ... 3).map { Mirror(type: .sniSpoof, endpoint: "192.0.2.\($0)", availableSniOptions: ["a.test", "b.test"]) }
        let resolver = MirrorResolver(bootstrap: MirrorsBootstrapService(urls: [], timeout: 1), mirrors: mirrors) {
            await MirrorResolver.isHealthy($0, sniTransport: SNISpoofTransport(timeout: 5), rootCAPublicKeys: [Data([1])], timeout: 5)
        }
        let task = Task { try await resolver.currentMirror() }
        try await Task.sleep(for: .milliseconds(200))

        let elapsed = await ContinuousClock().measure {
            task.cancel()
            _ = await task.result
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(elapsed < .seconds(2))
    }
}
