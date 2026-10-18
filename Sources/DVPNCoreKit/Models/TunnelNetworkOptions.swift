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

    public init(includeAllNetworks: Bool = false, excludeLocalNetworks: Bool? = nil, enforceRoutes: Bool = false) {
        self.includeAllNetworks = includeAllNetworks
        self.excludeLocalNetworks = excludeLocalNetworks
        self.enforceRoutes = enforceRoutes
    }

    /// No kill switch, routes not enforced, local networks as each engine has them.
    public static let `default` = TunnelNetworkOptions()
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
