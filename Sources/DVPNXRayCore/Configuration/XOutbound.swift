//
//  XOutbound.swift
//  DVPNCore
//

import Foundation

// MARK: - XOutbound

/// The proxy protocol of the Xray `proxy` outbound and its server settings.
///
/// Encodes as `{"protocol": "vless", "settings": {...}}`, where `settings` is the single
/// server entry (`vnext[0]` for VMess/VLESS, `servers[0]` for Trojan).
public enum XOutbound: Sendable, Equatable {
    case vmess(VMess)
    case vless(VLESS)
    case trojan(Trojan)

    public var protocolName: String {
        switch self {
        case .vmess: return "vmess"
        case .vless: return "vless"
        case .trojan: return "trojan"
        }
    }

    public var address: String {
        switch self {
        case let .vmess(vmess): return vmess.address
        case let .vless(vless): return vless.address
        case let .trojan(trojan): return trojan.address
        }
    }

    public var port: Int {
        switch self {
        case let .vmess(vmess): return vmess.port
        case let .vless(vless): return vless.port
        case let .trojan(trojan): return trojan.port
        }
    }
}

// MARK: - Codable

extension XOutbound: Codable {
    enum CodingKeys: String, CodingKey {
        case `protocol`
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .protocol)
        switch name {
        case "vmess":
            self = .vmess(try container.decode(VMess.self, forKey: .settings))
        case "vless":
            self = .vless(try container.decode(VLESS.self, forKey: .settings))
        case "trojan":
            self = .trojan(try container.decode(Trojan.self, forKey: .settings))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .protocol,
                in: container,
                debugDescription: "Unsupported Xray outbound protocol '\(name)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolName, forKey: .protocol)
        switch self {
        case let .vmess(vmess): try container.encode(vmess, forKey: .settings)
        case let .vless(vless): try container.encode(vless, forKey: .settings)
        case let .trojan(trojan): try container.encode(trojan, forKey: .settings)
        }
    }
}
