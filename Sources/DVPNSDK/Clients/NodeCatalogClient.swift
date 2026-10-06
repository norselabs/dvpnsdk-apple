//
//  NodeCatalogClient.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// The countries, their cities and a city's servers that serve the node types asked for (at least one), by load; and
/// one country by its ID.
public struct NodeCatalogClient: Sendable {
    public var country: @Sendable (_ id: String) async throws -> Country
    public var countries: @Sendable (_ nodeTypes: [NodeType]) async throws -> [Country]
    public var cities: @Sendable (_ countryID: String, _ nodeTypes: [NodeType]) async throws -> [City]
    public var servers: @Sendable (_ cityID: String, _ nodeTypes: [NodeType]) async throws -> [Server]

    public init(
        country: @escaping @Sendable (_ id: String) async throws -> Country,
        countries: @escaping @Sendable (_ nodeTypes: [NodeType]) async throws -> [Country],
        cities: @escaping @Sendable (_ countryID: String, _ nodeTypes: [NodeType]) async throws -> [City],
        servers: @escaping @Sendable (_ cityID: String, _ nodeTypes: [NodeType]) async throws -> [Server]
    ) {
        self.country = country
        self.countries = countries
        self.cities = cities
        self.servers = servers
    }
}

// MARK: - Live

public extension NodeCatalogClient {
    /// Sends through `httpClient`; the live value uses the process's.
    static func live(httpClient: any HTTPClient) -> Self {
        @Sendable func fetch<T: Decodable & Sendable>(_ target: CountriesAPITarget, as _: T.Type) async throws -> T {
            try await httpClient.execute(APIRequest(target: target), as: DataResponse<T>.self).data
        }
        return Self(
            country: { try await fetch(.country(countryID: $0), as: Country.self) },
            countries: { try await fetch(.countries(params: ServerParameters(nodeTypes: $0)), as: [Country].self) },
            cities: { try await fetch(.cities(countryID: $0, params: ServerParameters(nodeTypes: $1)), as: [City].self) },
            servers: { try await fetch(.cityServers(cityID: $0, params: ServerParameters(nodeTypes: $1)), as: [Server].self) }
        )
    }
}

// MARK: - DependencyKey

extension NodeCatalogClient: DependencyKey {
    public static let liveValue = Self.live(httpClient: ProcessHTTPClient())

    public static let testValue = Self(
        country: unimplemented("NodeCatalogClient.country"),
        countries: unimplemented("NodeCatalogClient.countries"),
        cities: unimplemented("NodeCatalogClient.cities"),
        servers: unimplemented("NodeCatalogClient.servers")
    )

    public static let previewValue = Self(
        country: { _ in Country(id: "de", name: "Germany", code: "DE", serversAvailable: 3) },
        countries: { _ in
            [
                Country(id: "de", name: "Germany", code: "DE", serversAvailable: 3),
                Country(id: "ee", name: "Estonia", code: "EE", serversAvailable: 1),
            ]
        },
        cities: { countryID, _ in [City(id: "ber", countryID: countryID, name: "Berlin", serversAvailable: 3)] },
        servers: { cityID, _ in
            [Server(id: "srv-1", countryID: "de", cityID: cityID, load: 0.2, name: "Berlin 1", isAvailable: true, serverProtocol: "XRAY")]
        }
    )
}

public extension DependencyValues {
    var nodeCatalog: NodeCatalogClient {
        get { self[NodeCatalogClient.self] }
        set { self[NodeCatalogClient.self] = newValue }
    }
}
