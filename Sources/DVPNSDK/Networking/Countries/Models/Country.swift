//
//  Country.swift
//  DVPNSDK
//

import Foundation

public struct Country: Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let code: String
    public let serversAvailable: Int

    public init(id: String, name: String, code: String, serversAvailable: Int) {
        self.id = id
        self.name = name
        self.code = code
        self.serversAvailable = serversAvailable
    }
}

extension Country: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case serversAvailable = "servers_available"
    }
}
