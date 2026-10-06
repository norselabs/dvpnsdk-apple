//
//  Server.swift
//  DVPNSDK
//

// MARK: - Server

public struct Server: Equatable, Sendable {
    public let id: String
    public let countryID: String
    public let cityID: String
    public let name: String
    public let load: Double
    public let isAvailable: Bool
    /// The node type as the backend sent it; kept as a string, since a server is stored and read back leniently.
    public let serverProtocol: String

    public var country: Country?

    public init(
        id: String,
        countryID: String,
        country: Country? = nil,
        cityID: String,
        load: Double = 0.5,
        name: String,
        isAvailable: Bool,
        serverProtocol: String
    ) {
        self.id = id
        self.countryID = countryID
        self.country = country
        self.cityID = cityID
        self.name = name
        self.load = load
        self.isAvailable = isAvailable
        self.serverProtocol = serverProtocol
    }
}

// MARK: - Node type

public extension Server {
    /// The node type the server serves, or nil for one this SDK does not know.
    var nodeType: NodeType? {
        NodeType(rawValue: serverProtocol.uppercased())
    }
}

// MARK: - Codable

extension Server: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case countryID = "country_id"
        case country
        case cityID = "city_id"
        case load
        case name
        case isAvailable = "is_available"
        case serverProtocol = "protocol"
    }
}
