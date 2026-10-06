//
//  TunnelProtocolDescriptor.swift
//  DVPNCore
//

import Foundation

// MARK: - TunnelProtocolID

/// The tunnel engines DVPNCore knows how to drive. Each one runs in its own
/// packet tunnel extension process. AmneziaWG is not an engine of its own: it is a
/// WireGuard configuration with extra `[Interface]` parameters, served by the WireGuard
/// extension (amneziawg-go is a superset of wireguard-go).
public enum TunnelProtocolID: String, Codable, Sendable, CaseIterable, Hashable {
    case wireGuard
    case xray
    case hysteria
}

// MARK: - TunnelReadiness

/// How the app learns that a `.connected` tunnel can actually carry traffic.
public enum TunnelReadiness: Sendable, Hashable {
    /// `.connected` already means traffic flows (proxy engines fronted by tun2socks).
    case immediate
    /// Poll the provider's runtime configuration (`handleAppMessage(Data([0]))`)
    /// until a peer reports `last_handshake_time_sec > 0`.
    case wireGuardHandshake
}

// MARK: - TunnelProtocolDescriptor

/// Per-app identity of one tunnel engine: which extension implements it and how
/// the system names it.
public struct TunnelProtocolDescriptor: Sendable, Hashable, Identifiable {
    public let id: TunnelProtocolID
    /// Bundle identifier of the packet tunnel extension implementing this protocol.
    public let providerBundleID: String
    /// `NETunnelProviderManager.localizedDescription`, what the system's VPN settings show. Engines are told apart
    /// by `providerBundleID`, so several descriptors may share a name (the apps name every engine's profile alike).
    public let tunnelName: String
    public let readiness: TunnelReadiness

    public init(
        id: TunnelProtocolID,
        providerBundleID: String,
        tunnelName: String,
        readiness: TunnelReadiness
    ) {
        self.id = id
        self.providerBundleID = providerBundleID
        self.tunnelName = tunnelName
        self.readiness = readiness
    }
}
