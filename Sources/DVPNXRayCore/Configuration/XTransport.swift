//
//  XTransport.swift
//  DVPNCore
//

import Foundation

// MARK: - XTransport

/// The stream transport of the proxy outbound, with the settings that belong to it.
/// Encodes as `{"network": "ws", "settings": {…}}`; `network` is the Xray `streamSettings.network` value.
public enum XTransport: Sendable, Equatable {
    case tcp(StreamSettings.TCP)
    case ws(StreamSettings.WebSocket)
    case grpc(StreamSettings.GRPC)
    case xhttp(StreamSettings.XHTTP)
    case httpupgrade(StreamSettings.HTTPUpgrade)

    /// Default settings for a network (the backend only names the transport).
    public init(network: XNetwork) {
        switch network {
        case .tcp: self = .tcp(.init())
        case .ws: self = .ws(.init())
        case .grpc: self = .grpc(.init())
        case .xhttp: self = .xhttp(.init())
        case .httpupgrade: self = .httpupgrade(.init())
        }
    }

    public var network: XNetwork {
        switch self {
        case .tcp: return .tcp
        case .ws: return .ws
        case .grpc: return .grpc
        case .xhttp: return .xhttp
        case .httpupgrade: return .httpupgrade
        }
    }

    /// The `streamSettings` key Xray expects for this transport and the encodable settings value.
    var streamSettingsEntry: (key: String, value: any Encodable) {
        switch self {
        case let .tcp(settings): return ("tcpSettings", settings)
        case let .ws(settings): return ("wsSettings", settings)
        case let .grpc(settings): return ("grpcSettings", settings)
        case let .xhttp(settings): return ("xhttpSettings", settings)
        case let .httpupgrade(settings): return ("httpupgradeSettings", settings)
        }
    }
}

// MARK: - Codable

extension XTransport: Codable {
    private enum CodingKeys: String, CodingKey {
        case network
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(XNetwork.self, forKey: .network) {
        case .tcp: self = .tcp(try container.decodeIfPresent(StreamSettings.TCP.self, forKey: .settings) ?? .init())
        case .ws: self = .ws(try container.decodeIfPresent(StreamSettings.WebSocket.self, forKey: .settings) ?? .init())
        case .grpc: self = .grpc(try container.decodeIfPresent(StreamSettings.GRPC.self, forKey: .settings) ?? .init())
        case .xhttp: self = .xhttp(try container.decodeIfPresent(StreamSettings.XHTTP.self, forKey: .settings) ?? .init())
        case .httpupgrade: self = .httpupgrade(try container.decodeIfPresent(StreamSettings.HTTPUpgrade.self, forKey: .settings) ?? .init())
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        switch self {
        case let .tcp(settings): try container.encode(settings, forKey: .settings)
        case let .ws(settings): try container.encode(settings, forKey: .settings)
        case let .grpc(settings): try container.encode(settings, forKey: .settings)
        case let .xhttp(settings): try container.encode(settings, forKey: .settings)
        case let .httpupgrade(settings): try container.encode(settings, forKey: .settings)
        }
    }
}
