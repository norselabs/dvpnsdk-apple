//
//  VLESS.swift
//  DVPNCore
//

import Foundation

// MARK: - VLESS

/// One `vnext` server entry of a VLESS outbound.
public struct VLESS: Codable, Sendable, Equatable {
    public struct User: Codable, Sendable, Equatable {
        public var id: String = ""
        public var encryption: String = "none"
        /// Omitted from JSON when `nil` (Xray-core rejects `"flow": null`).
        public var flow: XFlow?
        public var level: Int = 0

        public init(id: String = "", encryption: String = "none", flow: XFlow? = nil, level: Int = 0) {
            self.id = id
            self.encryption = encryption
            self.flow = flow
            self.level = level
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
