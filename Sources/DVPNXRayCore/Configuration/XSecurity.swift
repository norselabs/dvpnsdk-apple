//
//  XSecurity.swift
//  DVPNCore
//

import Foundation

// MARK: - XSecurity

/// Stream security of the proxy outbound, with the settings that belong to it.
/// Encodes as `{"security": "tls", "settings": {…}}`; `.none` carries no settings.
public enum XSecurity: Sendable, Equatable {
    case none
    case tls(StreamSettings.TLS)
    case reality(StreamSettings.Reality)
    /// Backend nodes, whose TLS is unknown (the backend sends host, port and transport only): the
    /// extension handshakes with the node once at every start. If the node offers TLS, the stream uses
    /// these settings pinned to the leaf certificate the node presented (the replacement for the
    /// `allowInsecure` option Xray-core 26.x removed); otherwise the stream is plaintext.
    /// Never rendered into Xray JSON: `XraySecurityResolver` turns it into `.tls` or `.none` first.
    case autodetect(StreamSettings.TLS)

    /// The `streamSettings.security` value Xray expects (`.autodetect` is the storage discriminator only).
    public enum Kind: String, Identifiable, CaseIterable, Codable, Sendable {
        public var id: Self { self }

        case none
        case tls
        case reality
        case autodetect
    }

    public var kind: Kind {
        switch self {
        case .none: return .none
        case .tls: return .tls
        case .reality: return .reality
        case .autodetect: return .autodetect
        }
    }
}

// MARK: - Codable

extension XSecurity: Codable {
    private enum CodingKeys: String, CodingKey {
        case security
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .security) {
        case .none: self = .none
        case .tls: self = .tls(try container.decodeIfPresent(StreamSettings.TLS.self, forKey: .settings) ?? .init())
        case .reality: self = .reality(try container.decodeIfPresent(StreamSettings.Reality.self, forKey: .settings) ?? .init())
        case .autodetect: self = .autodetect(try container.decodeIfPresent(StreamSettings.TLS.self, forKey: .settings) ?? .init())
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .security)
        switch self {
        case .none: break
        case let .tls(settings): try container.encode(settings, forKey: .settings)
        case let .reality(settings): try container.encode(settings, forKey: .settings)
        case let .autodetect(settings): try container.encode(settings, forKey: .settings)
        }
    }
}
