//
//  APIEndpointClient.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// Where requests go: `refresh` checks the API's `/health` and returns to it, or resolves a mirror; `diagnose` runs the
/// mirror resolution's lists, routes and probes, all of them, and reports every step. The live diagnostic reports a
/// failed step rather than throwing; a stand-in may throw.
public struct APIEndpointClient: Sendable {
    public var refresh: @Sendable () async -> Void
    public var diagnose: @Sendable () async throws -> DiagnosticReport

    public init(refresh: @escaping @Sendable () async -> Void, diagnose: @escaping @Sendable () async throws -> DiagnosticReport) {
        self.refresh = refresh
        self.diagnose = diagnose
    }
}

// MARK: - Live

public extension APIEndpointClient {
    /// Refreshes `httpClient`'s endpoint and diagnoses the mirrors `configuration` names.
    static func live(httpClient: any HTTPClient, configuration: @escaping @Sendable () -> BackendConfiguration) -> Self {
        Self(
            refresh: { await httpClient.refreshEndpoint() },
            diagnose: { await MirrorDiagnostic(configuration: configuration()).run() }
        )
    }
}

// MARK: - DependencyKey

extension APIEndpointClient: DependencyKey {
    public static let liveValue = Self.live(httpClient: ProcessHTTPClient()) {
        @Dependency(\.backendConfiguration) var configuration
        return configuration
    }

    public static let testValue = Self(
        refresh: unimplemented("APIEndpointClient.refresh"),
        diagnose: unimplemented("APIEndpointClient.diagnose")
    )
}

public extension DependencyValues {
    var apiEndpoint: APIEndpointClient {
        get { self[APIEndpointClient.self] }
        set { self[APIEndpointClient.self] = newValue }
    }
}
