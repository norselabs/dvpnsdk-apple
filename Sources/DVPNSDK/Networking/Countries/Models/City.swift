//
//  City.swift
//  DVPNSDK
//

import Foundation

public struct City: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let countryID: String
    public let name: String
    public let serversAvailable: Int

    public var country: Country?

    public init(id: String, countryID: String, name: String, serversAvailable: Int, country: Country? = nil) {
        self.id = id
        self.countryID = countryID
        self.name = name
        self.serversAvailable = serversAvailable
        self.country = country
    }

    enum CodingKeys: String, CodingKey {
        case id
        case countryID = "country_id"
        case name
        case country
        case serversAvailable = "servers_available"
    }

    /// The name comes from the node operators' data: it is kept as `String.displayName` shows it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        countryID = try container.decode(String.self, forKey: .countryID)
        name = try container.decode(String.self, forKey: .name).displayName
        serversAvailable = try container.decode(Int.self, forKey: .serversAvailable)
        country = try container.decodeIfPresent(Country.self, forKey: .country)
    }
}
