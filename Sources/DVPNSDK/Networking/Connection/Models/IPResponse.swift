//
//  IPResponse.swift
//  DVPNSDK
//

import Foundation

// MARK: - IPResponse

public struct IPResponse: Codable, Equatable, Sendable {
    public let ip: String
    public let information: IPLocation

    public init(ip: String, information: IPLocation) {
        self.ip = ip
        self.information = information
    }
}

// MARK: - IPLocation

public struct IPLocation: Equatable, Sendable {
    public let city: String
    public let country: String
    public let countryCode: String

    public let latitude: Double
    public let longitude: Double

    public init(city: String, country: String, countryCode: String, latitude: Double, longitude: Double) {
        self.city = city
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension IPLocation: Codable {
    enum CodingKeys: String, CodingKey {
        case city, country
        case countryCode = "country_code"
        case latitude, longitude
    }
}
