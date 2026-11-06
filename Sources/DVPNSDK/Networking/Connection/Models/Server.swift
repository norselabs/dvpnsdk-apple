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
    /// The node's address on the network (`sentnode…`), when the backend sent one.
    public let address: String?

    public var country: Country?

    public init(
        id: String,
        countryID: String,
        country: Country? = nil,
        cityID: String,
        load: Double = 0.5,
        name: String,
        isAvailable: Bool,
        serverProtocol: String,
        address: String? = nil
    ) {
        self.id = id
        self.countryID = countryID
        self.country = country
        self.cityID = cityID
        self.name = name
        self.load = load
        self.isAvailable = isAvailable
        self.serverProtocol = serverProtocol
        self.address = address
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
        case address
    }

    /// The name is the node operator's text: it is kept as `String.displayName` shows it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        countryID = try container.decode(String.self, forKey: .countryID)
        country = try container.decodeIfPresent(Country.self, forKey: .country)
        cityID = try container.decode(String.self, forKey: .cityID)
        load = try container.decode(Double.self, forKey: .load)
        name = try container.decode(String.self, forKey: .name).displayName
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        serverProtocol = try container.decode(String.self, forKey: .serverProtocol)
        address = try container.decodeIfPresent(String.self, forKey: .address)
    }
}
