//
//  XEncryption.swift
//  DVPNCore
//

import Foundation

// MARK: - XEncryption

public enum XEncryption: String, Identifiable, Codable, Sendable {
    public var id: Self { self }

    case aes_128_gcm = "aes-128-gcm"
    case chacha20_poly1305 = "chacha20-poly1305"
    case auto
    case none
    case zero
}

// MARK: - Static

public extension XEncryption {
    static let vmess: [XEncryption] = [.chacha20_poly1305, .aes_128_gcm, .auto, .none, .zero]
}
