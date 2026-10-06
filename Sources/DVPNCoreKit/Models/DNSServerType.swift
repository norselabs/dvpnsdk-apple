//
//  DNSServerType.swift
//  DVPNCore
//

import Foundation

// MARK: - DNSServerType

public enum DNSServerType: String, CaseIterable, Sendable {
    case cloudflare
    case google
    case quad9

    public var address: String {
        switch self {
        case .cloudflare:
            return "1.1.1.1, 1.0.0.1"
        case .google:
            return "8.8.8.8, 8.8.4.4"
        case .quad9:
            return "9.9.9.9, 149.112.112.112"
        }
    }

    public var addresses: [String] {
        address.splitToArray(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static var `default`: DNSServerType {
        .cloudflare
    }
}

// MARK: - Codable

extension DNSServerType: Codable {}

// MARK: - TunnelSettingsProviding

/// The tunnel layer's view of the app's settings storage.
public protocol TunnelSettingsProviding: AnyObject, Sendable {
    var selectedDNS: DNSServerType { get }
    /// "Advanced obfuscation": split the TLS ClientHello of Xray connections (Xray-core `fragment`,
    /// see `XObfuscation`). No effect on the other engines: AmneziaWG is obfuscated by design and a
    /// Hysteria 2 node dictates its own Salamander obfuscation.
    var isObfuscationEnabled: Bool { get }
}

public extension TunnelSettingsProviding {
    var isObfuscationEnabled: Bool { false }
}
