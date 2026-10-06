//
//  Trojan.swift
//  DVPNCore
//

import Foundation

// MARK: - Trojan

/// One `servers` entry of a Trojan outbound.
public struct Trojan: Codable, Sendable, Equatable {
    public var address: String = ""
    public var port: Int = 443
    public var password: String = ""
    public var level: Int = 0

    public init(address: String = "", port: Int = 443, password: String = "", level: Int = 0) {
        self.address = address
        self.port = port
        self.password = password
        self.level = level
    }
}
