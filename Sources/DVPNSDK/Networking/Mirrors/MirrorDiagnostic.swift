//
//  MirrorDiagnostic.swift
//  DVPNSDK
//

import Foundation

// MARK: - DiagnosticStep

/// A single logged step in the diagnostic cycle.
public struct DiagnosticStep: Identifiable, Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case success
        case failure(String)
        case info
        case skipped
    }

    public let id = UUID()

    public let timestamp: Date
    public let message: String
    public let result: Result

    public init(message: String, result: Result = .info) {
        timestamp = Date()
        self.message = message
        self.result = result
    }
}

// MARK: - DiagnosticReport

/// The full output of a diagnostic run.
public struct DiagnosticReport: Equatable, Sendable {
    public let steps: [DiagnosticStep]
    public let workingEndpoints: [String]
    public let startedAt: Date
    public let finishedAt: Date

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}

// MARK: - MirrorDiagnostic

/// Runs the mirror resolution the transport runs, but exhaustively: the same mirror lists (raced), the same routes and
/// the same health probes, all of them instead of the first healthy one, each reported as a step. By default it
/// pretends the primary is down.
public struct MirrorDiagnostic: Sendable {
    private let primaryURL: URL
    private let bootstrapURLs: [URL]
    private let rootCAPublicKeys: [Data]
    private let timeout: TimeInterval

    /// Probes the backend named by `configuration` and its mirrors.
    public init(configuration: BackendConfiguration) {
        primaryURL = configuration.backendURL
        bootstrapURLs = configuration.bootstrapMirrorURLs
        rootCAPublicKeys = configuration.rootCAPublicKeys
        timeout = configuration.mirrorRequestTimeout
    }

    /// Runs the full diagnostic cycle; callable from any context.
    public func run(skipPrimaryCheck: Bool = true) async -> DiagnosticReport {
        let startedAt = Date()
        var steps: [DiagnosticStep] = []
        func log(_ message: String, _ result: DiagnosticStep.Result = .info) {
            steps.append(DiagnosticStep(message: message, result: result))
        }
        func report(_ workingEndpoints: [String] = []) -> DiagnosticReport {
            DiagnosticReport(steps: steps, workingEndpoints: workingEndpoints, startedAt: startedAt, finishedAt: Date())
        }

        // The primary
        if skipPrimaryCheck {
            log("Primary endpoint (\(primaryURL.host ?? "?")) — SKIPPED (simulating failure)", .skipped)
        } else {
            log("Checking primary endpoint: \(primaryURL.host ?? "?")...")
            if await HealthCheck.succeeds(url: primaryURL.appendingPathComponent("health"), timeout: timeout) {
                log("Primary endpoint is healthy", .success)
                return report(["PRIMARY: \(primaryURL.absoluteString)"])
            }
            log("Primary endpoint unreachable", .failure("Health check failed"))
        }

        // The mirror list, raced as the transport races it
        log("Fetching the mirror list from \(bootstrapURLs.count) source(s) at once...")
        let mirrors: [Mirror]
        do {
            mirrors = try await MirrorsBootstrapService(urls: bootstrapURLs, timeout: timeout).fetch()
            log("Found \(mirrors.count) mirror(s)", .success)
        } catch {
            log("No mirror list from any source", .failure("Bootstrap failed"))
            return report()
        }
        if rootCAPublicKeys.isEmpty, mirrors.contains(where: { $0.type == .sniSpoof }) {
            log("No root CA public key configured — SNI mirrors cannot be trusted", .failure("Missing rootCAPublicKeys"))
        }

        // Every route of every mirror, probed in parallel, reported in the list's order
        let routes = mirrors.flatMap(MirrorResolver.routes(of:))
        log("Probing \(routes.count) route(s) of \(mirrors.count) mirror(s)...")
        let healthy = await probe(routes)
        var workingEndpoints: [String] = []
        for (route, isHealthy) in zip(routes, healthy) {
            let name = Self.endpointName(route)
            if isHealthy {
                log("  \(name): health check passed", .success)
                workingEndpoints.append(name)
            } else {
                log("  \(name): failed (connection, TLS or health check)", .failure("Unreachable or unhealthy"))
            }
        }

        if workingEndpoints.isEmpty {
            log("No working endpoints found", .failure("All mirrors failed"))
        } else {
            log("Found \(workingEndpoints.count) working endpoint(s)", .success)
        }
        return report(workingEndpoints)
    }
}

// MARK: - Probing

private extension MirrorDiagnostic {
    /// Whether each route is healthy, in the routes' order.
    func probe(_ routes: [MirrorResolver.Resolved]) async -> [Bool] {
        let transport = SNISpoofTransport(timeout: timeout)
        let (keys, timeout) = (rootCAPublicKeys, timeout)
        return await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, route) in routes.enumerated() {
                group.addTask {
                    (index, await MirrorResolver.isHealthy(route, sniTransport: transport, rootCAPublicKeys: keys, timeout: timeout))
                }
            }
            var healthy = Array(repeating: false, count: routes.count)
            for await (index, isHealthy) in group {
                healthy[index] = isHealthy
            }
            return healthy
        }
    }

    static func endpointName(_ route: MirrorResolver.Resolved) -> String {
        switch route {
        case let .regular(host):
            return "REGULAR: \(host)"
        case let .sniSpoof(ip, sni):
            return "SNI_SPOOF: \(ip) (sni=\(sni))"
        }
    }
}
