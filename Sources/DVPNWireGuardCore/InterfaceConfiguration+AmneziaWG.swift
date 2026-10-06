//
//  InterfaceConfiguration+AmneziaWG.swift
//  DVPNCore
//

import Foundation
import WireGuardKit

// MARK: - AmneziaWGParameterError

public enum AmneziaWGParameterError: LocalizedError, Equatable, Sendable {
    case unrecognizedKey(String)
    case invalidValue(key: String, value: String)

    public var errorDescription: String? {
        switch self {
        case let .unrecognizedKey(key):
            return "Unknown AmneziaWG parameter '\(key)'"
        case let .invalidValue(key, value):
            return "Invalid value '\(value)' for AmneziaWG parameter '\(key)'"
        }
    }
}

// MARK: - InterfaceConfiguration + AmneziaWG

public extension InterfaceConfiguration {
    /// Applies AmneziaWG `[Interface]` parameters given as raw ini attributes, the form the backend
    /// (and `AmneziaWGEndpoint.parameters`) uses: `["Jc": "4", "Jmin": "40", "H1": "1234567", …]`.
    /// Keys are matched case-insensitively; the kit's own wg-quick parser accepts the same names.
    mutating func applyAmneziaWG(_ parameters: [String: String]) throws(AmneziaWGParameterError) {
        for (key, rawValue) in parameters.sorted(by: { $0.key < $1.key }) {
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { throw .invalidValue(key: key, value: rawValue) }

            func number() throws(AmneziaWGParameterError) -> UInt16 {
                guard let number = UInt16(value) else { throw .invalidValue(key: key, value: rawValue) }
                return number
            }

            switch key.lowercased() {
            case "jc": junkPacketCount = try number()
            case "jmin": junkPacketMinSize = try number()
            case "jmax": junkPacketMaxSize = try number()
            case "s1": initPacketJunkSize = try number()
            case "s2": responsePacketJunkSize = try number()
            case "s3": cookieReplyPacketJunkSize = try number()
            case "s4": transportPacketJunkSize = try number()
            case "h1": initPacketMagicHeader = value
            case "h2": responsePacketMagicHeader = value
            case "h3": underloadPacketMagicHeader = value
            case "h4": transportPacketMagicHeader = value
            case "i1": specialJunk1 = value
            case "i2": specialJunk2 = value
            case "i3": specialJunk3 = value
            case "i4": specialJunk4 = value
            case "i5": specialJunk5 = value
            case "headerprotectionkey":
                guard let key = PrivateKey(base64Key: value) else { throw .invalidValue(key: key, value: rawValue) }
                headerProtectionKey = key
            case "contentpaddingaddition": contentPaddingAddition = value
            case "rekeyaftertime": rekeyAfterTime = value
            case "rekeytimeout": rekeyTimeout = value
            case "rejectaftertime": rejectAfterTime = value
            case "keepalivetimeout": keepaliveTimeout = value
            case "maxhandshakeattempts": maxHandshakeAttempts = value
            case "randomtrailers": randomTrailers = value
            case "disablecookies": disableCookies = value
            default:
                throw .unrecognizedKey(key)
            }
        }
    }

    /// `true` when any AmneziaWG parameter is set, i.e. the configuration is not plain WireGuard.
    var hasAmneziaWGParameters: Bool {
        junkPacketCount != nil || junkPacketMinSize != nil || junkPacketMaxSize != nil
            || initPacketJunkSize != nil || responsePacketJunkSize != nil
            || cookieReplyPacketJunkSize != nil || transportPacketJunkSize != nil
            || initPacketMagicHeader != nil || responsePacketMagicHeader != nil
            || underloadPacketMagicHeader != nil || transportPacketMagicHeader != nil
            || specialJunk1 != nil || specialJunk2 != nil || specialJunk3 != nil
            || specialJunk4 != nil || specialJunk5 != nil
            || headerProtectionKey != nil || contentPaddingAddition != nil
            || rekeyAfterTime != nil || rekeyTimeout != nil || rejectAfterTime != nil
            || keepaliveTimeout != nil || maxHandshakeAttempts != nil
            || randomTrailers != nil || disableCookies != nil
    }
}

// MARK: - TunnelConfiguration + AmneziaWG

public extension TunnelConfiguration {
    /// A copy with the AmneziaWG parameters applied to the interface; `self` when `parameters` is empty.
    func applyingAmneziaWG(_ parameters: [String: String]) throws(AmneziaWGParameterError) -> TunnelConfiguration {
        guard !parameters.isEmpty else { return self }
        var interface = interface
        try interface.applyAmneziaWG(parameters)
        return TunnelConfiguration(name: name, interface: interface, peers: peers)
    }

    var hasAmneziaWGParameters: Bool {
        interface.hasAmneziaWGParameters
    }
}

// MARK: - AmneziaWGJunkDefaults

/// Junk-packet settings are local to the client (they never have to match the server), so nodes do
/// not send them. These are the values used when a node's parameters carry none; they sit inside
/// amneziawg's accepted ranges (Jc 1–10, sizes 64–1024) and mirror what Sentinel's own client picks.
public enum AmneziaWGJunkDefaults {
    public static let parameters: [String: String] = ["Jc": "4", "Jmin": "64", "Jmax": "256"]

    /// `parameters` with the junk settings filled in where missing (case-insensitive key match).
    public static func filling(_ parameters: [String: String]) -> [String: String] {
        guard !parameters.isEmpty else { return parameters }
        var result = parameters
        let present = Set(parameters.keys.map { $0.lowercased() })
        for (key, value) in Self.parameters where !present.contains(key.lowercased()) {
            result[key] = value
        }
        return result
    }
}
