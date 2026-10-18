//
//  TunnelNetworkOptions.swift
//  DVPNSDK
//

import Foundation
import NetworkExtension

// MARK: - TunnelNetworkOptions

/// How the VPN profile routes the device's traffic, the same for every engine. `TunnelManager` reads them from
/// `TunnelSettingsProviding.networkOptions` whenever it saves the profile, at `start(from:)` and `restart()`. A running
/// tunnel keeps the options it started with: to apply a change, call `restart()`.
///
/// `default` is the SDK as it behaves without them: no kill switch, the system's routing, and each engine's own choice
/// for local networks.
public struct TunnelNetworkOptions: Hashable, Sendable, Codable {
    /// The kill switch: the system routes all traffic through the tunnel, whatever routes the network or apps set
    /// (`NEVPNProtocol.includeAllNetworks`), except what NetworkExtension always keeps out (DHCP, captive networks,
    /// cellular services the carrier routes itself, a paired watch) and, by the system's defaults, cellular services,
    /// push notifications and connected devices (`excludeCellularServices`, `excludeAPNs`,
    /// `excludeDeviceCommunication`). iOS and macOS; tvOS has no such setting.
    ///
    /// - Warning: Mullvad reports that with it on, an App Store update of the app can leave the device with no network
    ///   at all: the update stops the running extension, the system then lets no traffic out, and the download that
    ///   would install the new version waits for a network that never comes. A restart of the device usually recovers;
    ///   Mullvad found no way for an app to detect or avoid it
    ///   (<https://mullvad.net/en/blog/why-we-still-dont-use-includeallnetworks>, March 2025). Test an update with it on
    ///   before shipping it.
    public var includeAllNetworks: Bool

    /// Whether traffic to the local networks (the LAN: printers, AirPlay, a router's page) stays outside the tunnel
    /// (`NEVPNProtocol.excludeLocalNetworks`). It matters when `includeAllNetworks` or `enforceRoutes` is on. nil keeps
    /// each engine's own choice: the Xray and Hysteria profiles exclude local networks, the WireGuard profile keeps the
    /// system's default (excluded on iOS, included on macOS). iOS and macOS; tvOS has no such setting.
    public var excludeLocalNetworks: Bool?

    /// Whether the tunnel's routes take precedence over the routes the local network defines
    /// (`NEVPNProtocol.enforceRoutes`), so that a network cannot draw traffic outside the tunnel by announcing a more
    /// specific route (TunnelCrack's "LocalNet" attack).
    public var enforceRoutes: Bool

    /// Where IPv6 traffic goes. It lives in each engine's configuration rather than in the profile, and like the options
    /// above it applies when a tunnel starts or restarts.
    public var ipv6: IPv6Mode

    public init(
        includeAllNetworks: Bool = false,
        excludeLocalNetworks: Bool? = nil,
        enforceRoutes: Bool = false,
        ipv6: IPv6Mode = .unchanged
    ) {
        self.includeAllNetworks = includeAllNetworks
        self.excludeLocalNetworks = excludeLocalNetworks
        self.enforceRoutes = enforceRoutes
        self.ipv6 = ipv6
    }

    /// No kill switch, routes not enforced, local networks as each engine has them, IPv6 outside the tunnel.
    public static let `default` = TunnelNetworkOptions()
}

// MARK: - IPv6

public extension TunnelNetworkOptions {
    enum IPv6Mode: String, Hashable, Sendable, Codable, CaseIterable {
        /// As the SDK has always routed it: outside the tunnel, so on a network with IPv6, apps reach IPv6 destinations
        /// around the VPN.
        case unchanged
        /// All of it into the tunnel: through the node when the node carries IPv6, dropped when it does not, never
        /// around the tunnel. Apps fall back to IPv4 when an IPv6 connection fails.
        case tunnel
    }
}

// MARK: - Codable

public extension TunnelNetworkOptions {
    private enum CodingKeys: String, CodingKey {
        case includeAllNetworks, excludeLocalNetworks, enforceRoutes, ipv6
    }

    /// An option an earlier build did not store takes its default, so stored options keep decoding as options are added.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            includeAllNetworks: try container.decodeIfPresent(Bool.self, forKey: .includeAllNetworks) ?? false,
            excludeLocalNetworks: try container.decodeIfPresent(Bool.self, forKey: .excludeLocalNetworks),
            enforceRoutes: try container.decodeIfPresent(Bool.self, forKey: .enforceRoutes) ?? false,
            ipv6: try container.decodeIfPresent(IPv6Mode.self, forKey: .ipv6) ?? .unchanged
        )
    }
}

// MARK: - Profile

public extension NEVPNProtocol {
    /// Writes `options` onto a profile's protocol. When they leave `excludeLocalNetworks` nil, the engine's own choice
    /// (`engineDefault`) is written instead; without one, the property keeps the system's default.
    func apply(_ options: TunnelNetworkOptions, excludingLocalNetworksByDefault engineDefault: Bool? = nil) {
#if !os(tvOS)
        includeAllNetworks = options.includeAllNetworks
        if let excludeLocalNetworks = options.excludeLocalNetworks ?? engineDefault {
            self.excludeLocalNetworks = excludeLocalNetworks
        }
#endif
        enforceRoutes = options.enforceRoutes
    }

    /// Whether this protocol routes as a new one with `options` applied would: `false` means the profile must be saved
    /// again, and a running tunnel restarted, for the options to apply.
    func carries(_ options: TunnelNetworkOptions, excludingLocalNetworksByDefault engineDefault: Bool? = nil) -> Bool {
        let expected = NETunnelProviderProtocol()
        expected.apply(options, excludingLocalNetworksByDefault: engineDefault)
#if os(tvOS)
        return enforceRoutes == expected.enforceRoutes
#else
        return includeAllNetworks == expected.includeAllNetworks
            && excludeLocalNetworks == expected.excludeLocalNetworks
            && enforceRoutes == expected.enforceRoutes
#endif
    }
}
