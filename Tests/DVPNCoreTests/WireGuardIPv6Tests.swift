//
//  WireGuardIPv6Tests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing
@testable import WireGuardKit

/// IPv6 on a backend WireGuard node, checked on the network settings the extension applies: with `.tunnel` every IPv6
/// route goes into the tunnel, from the node's IPv6 address or a placeholder no node accepts; with `.unchanged` IPv6 is
/// routed as WireGuard nodes always had it, outside the tunnel.
@MainActor
struct WireGuardIPv6Tests {
    init() {
        DVPNCore.bootstrap(
            DVPNCoreConfiguration(
                appGroupID: "group.com.example.vpn.tests",
                protocols: [
                    TunnelProtocolDescriptor(
                        id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
                    ),
                    TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
                ]
            )
        )
    }

    @Test
    func tunnelledIPv6TakesTheDefaultRouteFromThePlaceholder() throws {
        let configuration = TunnelManager.configuration(try ipv4Node(), routingIPv6: .tunnel)

        let ipv6 = try #require(networkSettings(for: configuration).ipv6Settings)

        #expect(ipv6.includedRoutes?.contains(where: \.isDefault) == true)
        #expect(ipv6.addresses == [TunnelManager.placeholderIPv6Address])
        #expect(configuration.peers[0].allowedIPs.map(\.stringRepresentation) == ["0.0.0.0/0", "::/0"])
    }

    @Test
    func theNodesIPv6AddressIsTakenInsteadOfThePlaceholder() throws {
        let configuration = TunnelManager.configuration(
            try ipv4Node(), routingIPv6: .tunnel, nodeAddresses: ["10.8.1.2", "fd86:ea04:1115::2"]
        )

        let ipv6 = try #require(networkSettings(for: configuration).ipv6Settings)

        #expect(ipv6.addresses == ["fd86:ea04:1115::2"])
        #expect(ipv6.includedRoutes?.contains(where: \.isDefault) == true)
        #expect(configuration.interface.addresses.map(\.stringRepresentation) == ["10.8.1.2/32", "fd86:ea04:1115::2/128"])
    }

    @Test
    func unchangedIPv6HasNoRouteIntoTheTunnel() throws {
        let configuration = TunnelManager.configuration(try ipv4Node(), routingIPv6: .unchanged, nodeAddresses: ["10.8.1.2", "fd86:ea04:1115::2"])

        let settings = networkSettings(for: configuration)

        #expect(settings.ipv6Settings?.includedRoutes?.contains(where: \.isDefault) != true)
        #expect(settings.ipv6Settings?.addresses.isEmpty != false)
        #expect(configuration.interface == (try ipv4Node()).interface)
        #expect(configuration.peers == (try ipv4Node()).peers)
    }

    /// A restart after the option was turned off routes IPv6 as before it was on.
    @Test
    func turningItOffTakesOutWhatTunnellingAdded() throws {
        let tunnelled = TunnelManager.configuration(try ipv4Node(), routingIPv6: .tunnel)

        let restarted = TunnelManager.configuration(tunnelled, routingIPv6: .unchanged)

        #expect(restarted.interface == (try ipv4Node()).interface)
        #expect(restarted.peers == (try ipv4Node()).peers)
    }

    @Test
    func tunnellingTwiceAddsNothingTwice() throws {
        let once = TunnelManager.configuration(try ipv4Node(), routingIPv6: .tunnel)

        let twice = TunnelManager.configuration(once, routingIPv6: .tunnel)

        #expect(twice.interface == once.interface)
        #expect(twice.peers == once.peers)
    }

    /// The manager builds a backend node with the settings' IPv6 mode and the node's own IPv6 address.
    @Test
    func theManagerBuildsTheNodeWithItsIPv6Address() throws {
        let manager = TunnelManager(
            settings: FakeTunnelSettings(networkOptions: TunnelNetworkOptions(ipv6: .tunnel)),
            configuration: try #require(TunnelEnvironment.configuration)
        )
        manager.attach(TunnelsService(tunnelProviders: [], store: FakeTunnelProfileStore(), clock: StepClock()))
        let node = WireGuardEndpoint(
            host: "203.0.113.10",
            port: 51820,
            clientAddress: "10.8.0.2",
            peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=",
            clientAddresses: ["10.8.0.2", "fd86:ea04:1115::7"]
        )
        let credentials = ConnectionCredentials(
            nodeType: .wireguard, endpoint: .wireGuard(node), privateKey: "oK56DE9Ue9zHAt61A8xBeLjd9zLOUlGmk8hYB7sTf1k="
        )

        let configuration = try manager.wireGuardConfiguration(from: credentials)

        #expect(configuration.interface.addresses.map(\.stringRepresentation) == ["10.8.0.2/32", "fd86:ea04:1115::7/128"])
        #expect(configuration.peers[0].allowedIPs.map(\.stringRepresentation) == ["0.0.0.0/0", "::/0"])
    }

    // MARK: Helpers

    /// A backend node as `TunnelManager` writes it without IPv6.
    private func ipv4Node() throws -> TunnelConfiguration {
        try TunnelConfiguration(
            fromWgQuickConfig: """
            [Interface]
            PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
            Address = 10.8.1.2/32
            DNS = 1.1.1.1, 1.0.0.1

            [Peer]
            PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
            AllowedIPs = 0.0.0.0/0
            Endpoint = 203.0.113.10:51820
            PersistentKeepalive = 25
            """,
            called: "WireGuard"
        )
    }

    /// The settings the WireGuard extension applies for `configuration` (its endpoints are addresses already).
    private func networkSettings(for configuration: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        PacketTunnelSettingsGenerator(tunnelConfiguration: configuration, resolvedEndpoints: configuration.peers.map(\.endpoint))
            .generateNetworkSettings()
    }
}

private extension NEIPv6Route {
    var isDefault: Bool {
        destinationAddress == "::" && destinationNetworkPrefixLength.intValue == 0
    }
}
