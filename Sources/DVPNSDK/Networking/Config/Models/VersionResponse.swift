//
//  VersionResponse.swift
//  DVPNSDK
//

import Foundation

// MARK: - VersionResponse

public struct VersionResponse: Codable, Sendable {
    public let key: String
    public let value: String
}
