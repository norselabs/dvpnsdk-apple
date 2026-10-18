//
//  ProxyNetworkSettingsTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNProxyProviderCore
import Foundation
import NetworkExtension
import Testing

/// The network settings of the Xray and Hysteria tunnels: IPv4 always goes into the tunnel, IPv6 too when the app
/// routes it there, and never around it.
struct ProxyNetworkSettingsTests {
    @Test
    func tunnelledIPv6TakesTheDefaultRoute() throws {
        let settings = ProxyPacketTunnelProvider.networkSettings(
            network: NetworkModel(options: TunnelNetworkOptions(ipv6: .tunnel)), mtu: 9000, dnsServers: ["1.1.1.1"]
        )

        let ipv6 = try #require(settings.ipv6Settings)
        let ipv4Routes = settings.ipv4Settings?.includedRoutes ?? []
        #expect(ipv6.includedRoutes?.contains { $0.destinationAddress == "::" && $0.destinationNetworkPrefixLength.intValue == 0 } == true)
        #expect(ipv6.addresses == ["fd6e:a81b:704f:1211::1"])
        #expect(ipv4Routes.contains { $0.destinationAddress == "0.0.0.0" && $0.destinationSubnetMask == "0.0.0.0" })
    }

    @Test
    func byDefaultIPv6IsLeftOut() {
        let settings = ProxyPacketTunnelProvider.networkSettings(network: .default, mtu: 9000, dnsServers: ["1.1.1.1"])

        #expect(settings.ipv6Settings == nil)
        #expect(settings.ipv4Settings?.includedRoutes?.count == 1)
        #expect(settings.dnsSettings?.servers == ["1.1.1.1"])
    }

    @Test
    func theModelFollowsTheOptions() {
        #expect(NetworkModel(options: .default) == .default)
        #expect(NetworkModel(options: TunnelNetworkOptions(ipv6: .tunnel)).ipv6Enabled)
    }
}
