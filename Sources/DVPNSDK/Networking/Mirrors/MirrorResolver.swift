//
//  MirrorResolver.swift
//  DVPNSDK
//

import Foundation
import OSLog

private let log = Logger(subsystem: "com.dvpnsdk", category: "mirror")

/// The one owner of where requests go: whether they prefer a mirror, the mirror resolved for them, the mirror list,
/// and the routes that failed since the last refresh. The transport reports what happened; this decides.
actor MirrorResolver {
    /// A way to the API through a mirror.
    enum Resolved: Sendable, Hashable {
        /// A regular mirror: its domain replaces the API host.
        case regular(host: String)
        /// An SNI mirror's IP, reached as if DNS had resolved `sni` to it.
        case sniSpoof(ip: String, sni: String)
    }

    /// Whether a route answers its health check; the real probe, or a test's.
    typealias Probe = @Sendable (Resolved) async -> Bool

    private let bootstrap: MirrorsBootstrapService
    private let probe: Probe
    /// How long one resolution may take, the mirror list included, before it gives up.
    private let budget: Duration

    private var cached: Resolved?
    private var bootstrapped: [Mirror]?
    private var preferMirror = false
    /// Routes whose probe or request failed since the last refresh; a resolution skips them while others can be tried.
    private var failed: Set<Resolved> = []

    init(
        bootstrap: MirrorsBootstrapService,
        sniTransport: SNISpoofTransport,
        rootCAPublicKeys: [Data],
        healthTimeout: TimeInterval,
        budget: Duration = .seconds(30)
    ) {
        self.init(
            bootstrap: bootstrap,
            budget: budget,
            probe: { await Self.isHealthy($0, sniTransport: sniTransport, rootCAPublicKeys: rootCAPublicKeys, timeout: healthTimeout) }
        )
    }

    /// The seams the tests replace: the probe, a mirror list as if the bootstrap had returned it, a mirror as if a
    /// resolution had found it.
    init(
        bootstrap: MirrorsBootstrapService,
        budget: Duration = .seconds(30),
        mirrors: [Mirror]? = nil,
        resolved: Resolved? = nil,
        probe: @escaping Probe
    ) {
        self.bootstrap = bootstrap
        self.budget = budget
        self.probe = probe
        bootstrapped = mirrors
        cached = resolved
    }

    func currentMirror() async throws -> Resolved {
        if let cached { return cached }
        return try await resolveFromBootstrap()
    }

    func shouldPreferMirror() -> Bool {
        preferMirror
    }

    /// A request on `resolved` failed hard: it is dropped, skipped while other routes can be tried, and the list is
    /// fetched again for the next resolution.
    func invalidate(_ resolved: Resolved) {
        failed.insert(resolved)
        if cached == resolved {
            log.debug("invalidate — dropping cached mirror")
            cached = nil
            bootstrapped = nil
        }
    }

    /// The primary failed hard and a mirror answered: later requests go to the mirror until the next refresh.
    func mirrorAnswered() {
        preferMirror = true
    }

    /// No mirror answered: requests go to the primary, the only route left.
    func noMirrorAnswered() {
        preferMirror = false
    }

    /// The primary answers its health check: everything about mirrors is forgotten, and requests go to the primary.
    func primaryIsHealthy() {
        cached = nil
        bootstrapped = nil
        failed = []
        preferMirror = false
    }

    /// The primary does not answer: requests prefer a mirror, resolved afresh now.
    func primaryIsDown() async {
        preferMirror = true
        await refresh()
    }

    /// Forgets the resolved mirror, the list and the failed routes, and resolves again.
    @discardableResult
    func refresh() async -> Resolved? {
        log.debug("refresh start — clearing caches")
        cached = nil
        bootstrapped = nil
        failed = []
        do {
            let resolved = try await resolveFromBootstrap()
            log.debug("refresh success")
            return resolved
        } catch is CancellationError {
            log.debug("refresh cancelled")
            return nil
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Resolution

private extension MirrorResolver {
    /// What one mirror's probes came to.
    enum Outcome: Sendable {
        case probed(found: Resolved?, failed: [Resolved])
        case budgetSpent
    }

    /// Probes the list's routes, skipping the ones remembered as failed. When that finds nothing and routes were
    /// skipped, those are probed once more: a remembered failure may be over (a mirror that was down, a network that
    /// let nothing through), and skipping them would leave no mirror until the next refresh. Two passes at most, each
    /// route probed at most once, both within the one budget: a resolution always ends.
    func resolveFromBootstrap() async throws -> Resolved {
        let deadline = ContinuousClock.now.advanced(by: budget)
        let mirrors = try await mirrorList()
        let remembered = failed.intersection(mirrors.flatMap(Self.routes(of:)))
        log.debug("resolveFromBootstrap probing \(mirrors.count) mirror(s) in parallel, \(remembered.count) route(s) skipped")
        var (found, newlyFailed) = await probeInParallel(mirrors, skipping: remembered, until: deadline)
        failed.formUnion(newlyFailed)
        if found == nil, !remembered.isEmpty, !Task.isCancelled, ContinuousClock.now < deadline {
            log.debug("resolveFromBootstrap found none — probing the \(remembered.count) skipped route(s) once more")
            failed.subtract(remembered)
            (found, newlyFailed) = await probeInParallel(mirrors, skipping: failed, until: deadline)
            failed.formUnion(newlyFailed)
        }
        // A caller that gave up (the app's limit on its lookup, a replaced request) is told so, not "no mirror".
        try Task.checkCancellation()
        guard let found else {
            log.error("resolveFromBootstrap exhausted — no healthy mirror")
            throw MirrorError.noHealthyMirror
        }
        log.debug("resolveFromBootstrap found a mirror")
        cached = found
        return found
    }

    /// One pass: every mirror at once, the first healthy route wins and stops the rest, and the deadline stops them all.
    /// Returns the route found, if any, and the routes that failed on the way.
    func probeInParallel(
        _ mirrors: [Mirror],
        skipping skipped: Set<Resolved>,
        until deadline: ContinuousClock.Instant
    ) async -> (found: Resolved?, failed: [Resolved]) {
        let probe = probe
        let budget = budget
        return await withTaskGroup(of: Outcome.self) { group -> (Resolved?, [Resolved]) in
            for mirror in mirrors {
                group.addTask { await Self.probeRoutes(of: mirror, skipping: skipped, with: probe) }
            }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                return .budgetSpent
            }
            var failures: [Resolved] = []
            var pending = mirrors.count
            while pending > 0, let outcome = await group.next() {
                switch outcome {
                case let .probed(found, failed):
                    failures += failed
                    if let found {
                        group.cancelAll()
                        return (found, failures)
                    }
                    pending -= 1
                case .budgetSpent:
                    log.error("resolveFromBootstrap gave up after \(budget)")
                    group.cancelAll()
                    return (nil, failures)
                }
            }
            group.cancelAll()
            return (nil, failures)
        }
    }

    func mirrorList() async throws -> [Mirror] {
        if let cached = bootstrapped { return cached }
        let mirrors = try await bootstrap.fetch()
        bootstrapped = mirrors
        return mirrors
    }

    /// One mirror's routes, one after another (a mirror's SNI names in turn), until one is healthy. A probe cut short
    /// by cancellation says nothing about its route, so it is not counted as failed.
    static func probeRoutes(of mirror: Mirror, skipping skipped: Set<Resolved>, with probe: Probe) async -> Outcome {
        var failures: [Resolved] = []
        for route in routes(of: mirror) where !skipped.contains(route) {
            guard !Task.isCancelled else { break }
            if await probe(route) { return .probed(found: route, failed: failures) }
            guard !Task.isCancelled else { break }
            log.debug("probe failed")
            failures.append(route)
        }
        return .probed(found: nil, failed: failures)
    }
}

// MARK: - Routes and probes

extension MirrorResolver {
    /// The routes a mirror offers: its domain, or its IP with each SNI name in the list's order.
    static func routes(of mirror: Mirror) -> [Resolved] {
        switch mirror.type {
        case .regular:
            return [.regular(host: mirror.endpoint)]
        case .sniSpoof:
            return (mirror.availableSniOptions ?? []).map { .sniSpoof(ip: mirror.endpoint, sni: $0) }
        }
    }

    /// Whether `route` answers `GET /health` with `OK`. An SNI route needs a root key to trust its certificate.
    static func isHealthy(
        _ route: Resolved,
        sniTransport: SNISpoofTransport,
        rootCAPublicKeys: [Data],
        timeout: TimeInterval
    ) async -> Bool {
        switch route {
        case let .regular(host):
            guard let url = URL(string: "https://\(host)/health") else { return false }
            return await HealthCheck.succeeds(url: url, timeout: timeout)
        case let .sniSpoof(ip, sni):
            guard !rootCAPublicKeys.isEmpty, let url = URL(string: "https://\(sni)/health") else { return false }
            do {
                let (data, response) = try await sniTransport.send(URLRequest(url: url), ip: ip, sni: sni, rootCAPublicKeys: rootCAPublicKeys)
                guard (200 ..< 300).contains(response.statusCode) else { return false }
                try HealthCheck.validate(data)
                return true
            } catch {
                return false
            }
        }
    }
}
