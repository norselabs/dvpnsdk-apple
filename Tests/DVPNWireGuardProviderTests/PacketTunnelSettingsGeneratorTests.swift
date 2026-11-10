//
//  PacketTunnelSettingsGeneratorTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNWireGuardProvider
import Foundation
import NetworkExtension
import Testing
@testable import WireGuardKit

/// The network settings WireGuardKit's generator makes for a WireGuard or AmneziaWG tunnel, given the DNS settings
/// `WireGuardPacketTunnelProvider` hands the adapter. The provider and its adapter cannot be made outside an
/// extension, so no test reaches the two lines that hand them over.
struct PacketTunnelSettingsGeneratorTests {
    /// The tunnel's lookups go to the chosen provider over HTTPS, at its own addresses, for every name, and never
    /// fall back to plain DNS, which the node could read and answer.
    @Test(arguments: DNSServerType.allCases)
    func lookupsGoToTheProviderOverHTTPS(provider: DNSServerType) throws {
        let settings = try generator(dns: provider.address).generateNetworkSettings()

        let dns = try #require(settings.dnsSettings as? NEDNSOverHTTPSSettings)
        #expect(dns.dnsProtocol == .HTTPS)
        #expect(dns.serverURL?.absoluteString == provider.dnsOverHTTPSURL)
        #expect(dns.servers == provider.addresses)
        #expect(dns.matchDomains == [""])
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            #expect(!dns.allowFailover)
        }
    }

    /// Resolvers of no provider, as a configuration of an app's own making can name, stay plain DNS.
    @Test
    func otherResolversStayPlainDNS() throws {
        let settings = try generator(dns: "203.0.113.53").generateNetworkSettings()

        let dns = try #require(settings.dnsSettings)
        #expect(dns.dnsProtocol == .cleartext)
        #expect(dns.servers == ["203.0.113.53"])
        #expect(dns.matchDomains == [""])
    }

    /// A node's address gets no route outside the tunnel, in either family.
    @Test
    func aNodesAddressGetsNoRouteOutsideTheTunnel() throws {
        let settings = try generator(dns: "1.1.1.1").generateNetworkSettings()

        #expect(settings.ipv4Settings?.excludedRoutes?.map(\.destinationAddress) == [])
        #expect(settings.ipv6Settings?.excludedRoutes?.map(\.destinationAddress) == [])
    }

    /// The ranges a peer's configuration excludes still leave the tunnel.
    @Test
    func aPeersExcludedRangesStayOutsideTheTunnel() throws {
        let ranges = try [#require(IPAddressRange(from: "192.0.2.0/24")), #require(IPAddressRange(from: "2001:db8:1::/48"))]
        let settings = try generator(dns: "1.1.1.1", excluding: ranges).generateNetworkSettings()

        #expect(settings.ipv4Settings?.excludedRoutes?.map(\.destinationAddress) == ["192.0.2.0"])
        #expect(settings.ipv6Settings?.excludedRoutes?.map(\.destinationAddress) == ["2001:db8:1::"])
    }

    /// A generator with the provider's DNS settings, for a node at an IPv4 and an IPv6 address;
    /// `excluded` are its first peer's excluded ranges.
    private func generator(dns: String, excluding excluded: [IPAddressRange] = []) throws -> PacketTunnelSettingsGenerator {
        let configuration = try TunnelConfiguration(
            fromWgQuickConfig: """
            [Interface]
            PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
            Address = 10.8.1.2/32
            DNS = \(dns)

            [Peer]
            PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
            AllowedIPs = 0.0.0.0/0, ::/0
            Endpoint = 203.0.113.10:51820

            [Peer]
            PublicKey = HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw=
            AllowedIPs = 10.9.0.0/16
            Endpoint = [2001:db8::10]:51820
            """,
            called: "WireGuard"
        )
        configuration.peers[0].excludeIPs = excluded
        return PacketTunnelSettingsGenerator(
            tunnelConfiguration: configuration,
            resolvedEndpoints: configuration.peers.map(\.endpoint),
            dnsSettings: WireGuardPacketTunnelProvider.dnsSettings
        )
    }
}
