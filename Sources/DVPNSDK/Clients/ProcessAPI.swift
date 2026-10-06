//
//  ProcessAPI.swift
//  DVPNSDK
//

import Dependencies
import Foundation
import Synchronization

// MARK: - Dependencies

public extension DependencyValues {
    /// What every request goes through. Live: the backend's `MirroredTransport`, built from `backendConfiguration` when
    /// the first request needs it. An app can put a stand-in in front of it (a UI test's backend states) with
    /// `prepareDependencies`, before the first request.
    var apiTransport: any APITransport {
        get { self[APITransportKey.self] }
        set { self[APITransportKey.self] = newValue }
    }

    /// The process's one `HTTPClient`, on `apiTransport`: the clients send through it, and so can an app's own
    /// requests (another API on the same backend). One per process, since the mirror the transport fell back to and
    /// the device events the client publishes belong to the process.
    var apiClient: any HTTPClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

private enum APITransportKey: DependencyKey {
    static let liveValue: any APITransport = ProcessTransport()
    static let testValue: any APITransport = UnimplementedTransport()
}

private enum APIClientKey: DependencyKey {
    static let liveValue: any HTTPClient = ProcessHTTPClient()
    static let testValue: any HTTPClient = UnimplementedHTTPClient()
}

// MARK: - The process's transport and client

/// The backend's transport, built on first use from the `backendConfiguration` dependency. Never in a one-time
/// initializer: a dependency resolved there can deadlock against a live value resolved on another thread.
struct ProcessTransport: APITransport {
    private static let built = Mutex<MirroredTransport?>(nil)

    private var transport: MirroredTransport {
        Self.built.withLock { built in
            if let built { return built }
            @Dependency(\.backendConfiguration) var configuration
            let transport = MirroredTransport(configuration: configuration)
            built = transport
            return transport
        }
    }

    func send(_ request: APIRequest, headers: [String: String]) async throws -> APIResponse {
        try await transport.send(request, headers: headers)
    }

    func refreshEndpoint() async {
        await transport.refreshEndpoint()
    }
}

/// The process's `DefaultHTTPClient`, built on first use on the `apiTransport` dependency, so a stand-in transport
/// the app set before the first request is the one used.
struct ProcessHTTPClient: HTTPClient {
    private static let built = Mutex<DefaultHTTPClient?>(nil)

    private var client: DefaultHTTPClient {
        Self.built.withLock { built in
            if let built { return built }
            @Dependency(\.apiTransport) var transport
            let client = DefaultHTTPClient(transport: transport)
            built = client
            return client
        }
    }

    func execute<T: Decodable & Sendable>(_ request: APIRequest, requestHeaders: [String: String], as type: T.Type) async throws -> T {
        try await client.execute(request, requestHeaders: requestHeaders, as: type)
    }

    func refreshEndpoint() async {
        await client.refreshEndpoint()
    }

    func deviceEvents() -> AsyncStream<DeviceEvent> {
        client.deviceEvents()
    }
}

// MARK: - Unimplemented

/// A test that reaches the network without saying so fails, instead of sending.
private struct UnimplementedTransport: APITransport {
    func send(_ request: APIRequest, headers _: [String: String]) async throws -> APIResponse {
        reportIssue("Unimplemented: apiTransport.send(\(request.target.path))")
        throw URLError(.notConnectedToInternet)
    }

    func refreshEndpoint() async {
        reportIssue("Unimplemented: apiTransport.refreshEndpoint")
    }
}

private struct UnimplementedHTTPClient: HTTPClient {
    func execute<T: Decodable & Sendable>(_ request: APIRequest, requestHeaders _: [String: String], as _: T.Type) async throws -> T {
        reportIssue("Unimplemented: apiClient.execute(\(request.target.path))")
        throw URLError(.notConnectedToInternet)
    }

    func refreshEndpoint() async {
        reportIssue("Unimplemented: apiClient.refreshEndpoint")
    }

    func deviceEvents() -> AsyncStream<DeviceEvent> {
        reportIssue("Unimplemented: apiClient.deviceEvents")
        return AsyncStream { $0.finish() }
    }
}

// MARK: - Timeouts

/// Every request's timeout, in one place. The mirror lists and probes take
/// `BackendConfiguration.mirrorRequestTimeout` (5 s unless the app says otherwise), and a whole mirror resolution
/// gives up after 30 s (`MirrorResolver`).
public enum RequestTimeout {
    public static let standard: TimeInterval = 15
    public static let config: TimeInterval = 5
    /// The IP lookup is short: the app retries it, and a tunnel that just came up answers it at once.
    public static let publicIP: TimeInterval = 3
    /// Credentials wait for the node handshake; a minute bounds how long Home can show "Creating new DVPN session…"
    /// per attempt (a primary that times out is still retried on a mirror).
    public static let credentials: TimeInterval = 60
}
