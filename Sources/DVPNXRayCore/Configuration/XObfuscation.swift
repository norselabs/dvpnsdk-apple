//
//  XObfuscation.swift
//  DVPNCore
//

import Foundation

// MARK: - XObfuscation

/// Traffic obfuscation applied on top of the proxy outbound's transport.
/// Encodes as `{"mode": "tlsFragment", "settings": {…}}`; `.none` carries no settings.
///
/// `.tlsFragment` is Xray-core's `fragment` feature: the proxy outbound dials through a `freedom`
/// outbound (`sockopt.dialerProxy`) that splits the TLS ClientHello into several TCP segments, so
/// SNI-based filtering cannot read the server name from the first packet. It only touches TLS
/// handshakes (`packets: "tlshello"`); a plaintext or REALITY-less stream passes through unchanged.
public enum XObfuscation: Sendable, Equatable {
    case none
    case tlsFragment(FragmentSettings)

    /// Xray `freedom.settings.fragment`. Ranges are Xray strings (`"min-max"`).
    public struct FragmentSettings: Codable, Sendable, Equatable {
        /// `"tlshello"` fragments the TLS ClientHello only; `"1-3"` would fragment the first TCP packets instead.
        public var packets: String = "tlshello"
        /// Fragment length in bytes.
        public var length: String = "100-200"
        /// Delay between fragments in milliseconds.
        public var interval: String = "10-20"

        public init(packets: String = "tlshello", length: String = "100-200", interval: String = "10-20") {
            self.packets = packets
            self.length = length
            self.interval = interval
        }
    }

    public enum Mode: String, Codable, Sendable, CaseIterable {
        case none
        case tlsFragment
    }

    public var mode: Mode {
        switch self {
        case .none: return .none
        case .tlsFragment: return .tlsFragment
        }
    }

    public var isEnabled: Bool { self != .none }
}

// MARK: - Codable

extension XObfuscation: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .none: self = .none
        case .tlsFragment: self = .tlsFragment(try container.decodeIfPresent(FragmentSettings.self, forKey: .settings) ?? .init())
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        switch self {
        case .none: break
        case let .tlsFragment(settings): try container.encode(settings, forKey: .settings)
        }
    }
}
