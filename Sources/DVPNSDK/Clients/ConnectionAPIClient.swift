//
//  ConnectionAPIClient.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// The device's public IP and its location, and the credentials of a node in a city, a country, on a server, or one
/// the backend picks.
///
/// A city, a country and the backend's pick match a single node type: the backend refuses a list there with a 404, and
/// with none it picks a WireGuard or V2Ray node, as for the apps that predate the other types. A server takes a list, so
/// an app that offers every node type sends them all; with none, the backend could keep to WireGuard and V2Ray.
public struct ConnectionAPIClient: Sendable {
    /// Over a new connection, so a tunnel that just came up is the one that answers.
    public var publicIP: @Sendable () async throws -> IPResponse
    public var cityCredentials: @Sendable (_ city: City, _ nodeType: NodeType?) async throws -> ConnectionCredentials
    public var countryCredentials: @Sendable (_ country: Country, _ nodeType: NodeType?) async throws -> ConnectionCredentials
    public var serverCredentials: @Sendable (_ server: Server, _ nodeTypes: [NodeType]) async throws -> ConnectionCredentials
    public var quickCredentials: @Sendable (_ nodeType: NodeType?) async throws -> ConnectionCredentials

    public init(
        publicIP: @escaping @Sendable () async throws -> IPResponse,
        cityCredentials: @escaping @Sendable (_ city: City, _ nodeType: NodeType?) async throws -> ConnectionCredentials,
        countryCredentials: @escaping @Sendable (_ country: Country, _ nodeType: NodeType?) async throws -> ConnectionCredentials,
        serverCredentials: @escaping @Sendable (_ server: Server, _ nodeTypes: [NodeType]) async throws -> ConnectionCredentials,
        quickCredentials: @escaping @Sendable (_ nodeType: NodeType?) async throws -> ConnectionCredentials
    ) {
        self.publicIP = publicIP
        self.cityCredentials = cityCredentials
        self.countryCredentials = countryCredentials
        self.serverCredentials = serverCredentials
        self.quickCredentials = quickCredentials
    }
}

// MARK: - Live

public extension ConnectionAPIClient {
    /// Sends through `httpClient`; the live value uses the process's.
    static func live(httpClient: any HTTPClient) -> Self {
        @Sendable func credentials(_ target: ConnectionAPITarget) async throws -> ConnectionCredentials {
            let request = APIRequest(target: target, timeoutInterval: RequestTimeout.credentials)
            return try await httpClient.execute(request, as: DataResponse<ConnectionCredentials>.self).data
        }
        return Self(
            publicIP: {
                let request = APIRequest(target: ConnectionAPITarget.ip, timeoutInterval: RequestTimeout.publicIP, requiresFreshConnection: true)
                return try await httpClient.execute(request, as: DataResponse<IPResponse>.self).data
            },
            cityCredentials: { try await credentials(.credentialsCity(id: $0.id, body: CredentialsBody($1))) },
            countryCredentials: { try await credentials(.credentialsCountry(id: $0.id, body: CredentialsBody($1))) },
            serverCredentials: { try await credentials(.credentialsServer(id: $0.id, body: CredentialsBody($1))) },
            quickCredentials: { try await credentials(.quickCredentials(body: CredentialsBody($0))) }
        )
    }
}

// MARK: - DependencyKey

extension ConnectionAPIClient: DependencyKey {
    public static let liveValue = Self.live(httpClient: ProcessHTTPClient())

    public static let testValue = Self(
        publicIP: unimplemented("ConnectionAPIClient.publicIP"),
        cityCredentials: unimplemented("ConnectionAPIClient.cityCredentials"),
        countryCredentials: unimplemented("ConnectionAPIClient.countryCredentials"),
        serverCredentials: unimplemented("ConnectionAPIClient.serverCredentials"),
        quickCredentials: unimplemented("ConnectionAPIClient.quickCredentials")
    )
}

public extension DependencyValues {
    var connectionAPI: ConnectionAPIClient {
        get { self[ConnectionAPIClient.self] }
        set { self[ConnectionAPIClient.self] = newValue }
    }
}
