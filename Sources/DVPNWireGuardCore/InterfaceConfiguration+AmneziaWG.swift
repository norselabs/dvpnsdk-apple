//
//  InterfaceConfiguration+AmneziaWG.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import WireGuardKitTypes

// MARK: - AmneziaWGParameterError

/// The SDK writes no user text: `description` is for the log.
public enum AmneziaWGParameterError: Error, Equatable, Sendable, CustomStringConvertible {
    case unrecognizedKey(String)
    case invalidValue(key: String, value: String)

    public var description: String {
        switch self {
        case let .unrecognizedKey(key):
            return "Unknown AmneziaWG parameter '\(key)'"
        case let .invalidValue(key, value):
            // A value shows its length only: the header protection key is a secret the node shares with its clients, and
            // any other value is the node's text, which could read as lines of the log.
            return "Invalid value (\(value.count) characters) for AmneziaWG parameter '\(key.escapingControlCharacters)'"
        }
    }
}

// MARK: - InterfaceConfiguration + AmneziaWG

public extension InterfaceConfiguration {
    /// Applies AmneziaWG `[Interface]` parameters given as raw ini attributes, the form the backend
    /// (and `AmneziaWGEndpoint.parameters`) uses: `["Jc": "4", "Jmin": "40", "H1": "1234567", …]`.
    /// Keys are matched case-insensitively; the kit's own wg-quick parser accepts the same names.
    ///
    /// The values come from a node. Each is checked for what would harm the device, and the engine refuses the rest:
    /// no line break or control character, since the configuration is stored as wg-quick text the extension reads back
    /// line by line (a line break would add settings of the node's choice) and handed to the engine as a C string (a
    /// NUL would cut it); `S4` at most `AmneziaWGLimits.transportJunkSize`; and `I1`–`I5` as
    /// `AmneziaWGLimits.specialJunkSize(of:)` reads them.
    mutating func applyAmneziaWG(_ parameters: [String: String]) throws(AmneziaWGParameterError) {
        for (key, rawValue) in parameters.sorted(by: { $0.key < $1.key }) {
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            let breaksALine = value.unicodeScalars.contains {
                [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
            }
            guard !value.isEmpty, !breaksALine else { throw .invalidValue(key: key, value: rawValue) }

            func number() throws(AmneziaWGParameterError) -> UInt16 {
                guard let number = UInt16(value) else { throw .invalidValue(key: key, value: rawValue) }
                return number
            }

            func specialJunk() throws(AmneziaWGParameterError) -> String {
                guard AmneziaWGLimits.specialJunkSize(of: value) != nil else { throw .invalidValue(key: key, value: rawValue) }
                return value
            }

            switch key.lowercased() {
            case "jc": junkPacketCount = try number()
            case "jmin": junkPacketMinSize = try number()
            case "jmax": junkPacketMaxSize = try number()
            case "s1": initPacketJunkSize = try number()
            case "s2": responsePacketJunkSize = try number()
            case "s3": cookieReplyPacketJunkSize = try number()
            case "s4":
                let size = try number()
                guard size <= AmneziaWGLimits.transportJunkSize else { throw .invalidValue(key: key, value: rawValue) }
                transportPacketJunkSize = size
            case "h1": initPacketMagicHeader = value
            case "h2": responsePacketMagicHeader = value
            case "h3": underloadPacketMagicHeader = value
            case "h4": transportPacketMagicHeader = value
            case "i1": specialJunk1 = try specialJunk()
            case "i2": specialJunk2 = try specialJunk()
            case "i3": specialJunk3 = try specialJunk()
            case "i4": specialJunk4 = try specialJunk()
            case "i5": specialJunk5 = try specialJunk()
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

// MARK: - AmneziaWGLimits

/// The sizes a node's AmneziaWG values may reach, where the engine would crash past them.
enum AmneziaWGLimits {
    /// The most `S4` leaves room for: the engine reads a packet from the tunnel into a 1700-byte buffer on iOS and tvOS
    /// (amneziawg-go's `MaxSegmentSize`) at offset 16 (the transport header) + `S4`, and seals it there with a 16-byte
    /// tag. With the 1280-byte MTU WireGuardKit sets on iOS and tvOS when the configuration names none (the apps leave
    /// it empty), 1700 − 16 − 1280 − 16 = 388; past 1688 the engine panics on the first packet. A larger MTU lowers it.
    static let transportJunkSize: UInt16 = 388

    /// The most bytes one I-packet, sent as one datagram, may hold.
    static let specialJunkMaxSize = 1280

    /// The bytes the I-packet `value` makes, or nil when the engine could not build it safely: nothing but tags,
    /// whitespace between and inside them, each `<b hex>` (bytes, `0x` allowed), `<t>` (a 4-byte timestamp) or `<r n>`,
    /// `<rc n>`, `<rd n>` (n random bytes, letters or digits), at most `specialJunkMaxSize` in all. The engine takes a
    /// negative n and then panics making the packet, and a huge one allocates it; it also knows `<d>`, `<ds>` and
    /// `<dz n>`, which carry the packet's data and have none in an I-packet (`<dz>` has the same negative size).
    static func specialJunkSize(of value: String) -> Int? {
        var size = 0
        var rest = Substring(value)
        while let open = rest.firstIndex(where: { !$0.isWhitespace }) {
            guard rest[open] == "<", let close = rest[open...].firstIndex(of: ">") else { return nil }
            let parts = rest[rest.index(after: open) ..< close].split(whereSeparator: \.isWhitespace)
            rest = rest[rest.index(after: close)...]
            guard let tag = parts.first else { return nil }
            let argument = parts.count > 1 ? parts[1] : ""
            switch tag {
            case "b":
                let hex = argument.hasPrefix("0x") ? argument.dropFirst(2) : argument
                guard !hex.isEmpty, hex.count.isMultiple(of: 2), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
                size += hex.count / 2
            case "t":
                size += 4
            case "r", "rc", "rd":
                guard let count = Int(argument), (0 ... specialJunkMaxSize).contains(count) else { return nil }
                size += count
            default:
                return nil
            }
            guard size <= specialJunkMaxSize else { return nil }
        }
        return size
    }
}

// MARK: - AmneziaWGJunkDefaults

/// Junk-packet settings are local to the client (they never have to match the server), so the SDK takes
/// none a node sends. These are the values used instead; they sit inside
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
