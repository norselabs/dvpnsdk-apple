//
//  VMess.swift
//  DVPNCore
//

import Foundation

// MARK: - VMess

public struct VMess: Codable, Sendable, Equatable {
    public struct User: Codable, Sendable, Equatable {
        public var id: String = ""
        public var alterId: Int = 0
        public var security = XEncryption.auto

        public init(id: String = "", alterId: Int = 0, security: XEncryption = .auto) {
            self.id = id
            self.alterId = alterId
            self.security = security
        }
    }

    public var address: String = ""
    public var port: Int = 443
    public var users: [User] = [User()]

    public init(address: String = "", port: Int = 443, users: [User] = [User()]) {
        self.address = address
        self.port = port
        self.users = users
    }
}
