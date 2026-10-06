//
//  VerifyDeviceResponse.swift
//  DVPNSDK
//

import Foundation

// MARK: - VerifyDeviceResponse

public struct VerifyDeviceResponse: Sendable {
    public let id: String
    public let isEnrolled: Bool
    public let isBanned: Bool
}

// MARK: - Decodable

extension VerifyDeviceResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case isEnrolled = "is_enrolled"
        case isBanned = "is_banned"
    }
}
