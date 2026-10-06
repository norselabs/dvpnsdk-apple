//
//  XConfiguration.swift
//  DVPNCore
//

import Foundation

// MARK: - XConfigurationModel

/// The typed description of the Xray `proxy` outbound: what to connect to (`outbound`), over which
/// transport, with which security. Every part is a sum type, so an inconsistent configuration (TLS
/// without TLS settings, two transports at once) cannot be expressed. Rendered into Xray JSON by
/// `proxyOutbound()`; stored inside `XraySource` in the App Group.
public struct XConfigurationModel: Codable, Sendable, Equatable {
    public var outbound: XOutbound
    public var transport: XTransport
    public var security: XSecurity
    /// The app's "Advanced obfuscation" setting at connect time. Absent in files written by older
    /// app versions, which decode as `.none`.
    public var obfuscation: XObfuscation

    public init(
        outbound: XOutbound,
        transport: XTransport = .tcp(.init()),
        security: XSecurity = .none,
        obfuscation: XObfuscation = .none
    ) {
        self.outbound = outbound
        self.transport = transport
        self.security = security
        self.obfuscation = obfuscation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outbound = try container.decode(XOutbound.self, forKey: .outbound)
        transport = try container.decode(XTransport.self, forKey: .transport)
        security = try container.decode(XSecurity.self, forKey: .security)
        obfuscation = try container.decodeIfPresent(XObfuscation.self, forKey: .obfuscation) ?? .none
    }
}

// MARK: - XConfigurationError

public enum XConfigurationError: LocalizedError, Equatable, Sendable {
    /// `XSecurity.autodetect` reached the renderer; the extension must resolve it (`XraySecurityResolver`) first.
    case unresolvedSecurity

    public var errorDescription: String? {
        switch self {
        case .unresolvedSecurity:
            return "Xray security is not resolved: TLS must be detected before the configuration is rendered."
        }
    }
}
