//
//  WireGuardDNSOverHTTPSTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing
@testable import WireGuardKit

/// DNS over HTTPS in a WireGuard tunnel: the stored configuration keeps the DoH URL next to the plain servers, and the
/// extension's network settings ask that URL at those servers.
@MainActor
struct WireGuardDNSOverHTTPSTests {
    private let encrypted = """
    [Interface]
    PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
    Address = 10.8.1.2/32
    DNS = 9.9.9.9, 149.112.112.112
    DNSOverHTTPS = https://dns.quad9.net/dns-query

    [Peer]
    PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
    AllowedIPs = 0.0.0.0/0
    Endpoint = 203.0.113.10:51820
    """

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
    func theDoHURLRoundTripsThroughTheStoredText() throws {
        let configuration = try TunnelConfiguration(fromWgQuickConfig: encrypted, called: "WireGuard")

        #expect(configuration.interface.dnsOverHTTPSURL?.absoluteString == "https://dns.quad9.net/dns-query")
        let reparsed = try TunnelConfiguration(fromWgQuickConfig: configuration.asWgQuickConfig(), called: "WireGuard")
        #expect(reparsed.interface == configuration.interface)
    }

    @Test
    func aDoHURLThatIsNotHTTPSIsRefused() {
        let plainHTTP = encrypted.replacingOccurrences(of: "https://", with: "http://")

        #expect(throws: TunnelConfiguration.ParseError.self) {
            try TunnelConfiguration(fromWgQuickConfig: plainHTTP, called: "WireGuard")
        }
    }

    @Test
    func theNetworkSettingsAskTheDoHURL() throws {
        let configuration = try TunnelConfiguration(fromWgQuickConfig: encrypted, called: "WireGuard")

        let dns = try #require(networkSettings(for: configuration).dnsSettings as? NEDNSOverHTTPSSettings)

        #expect(dns.serverURL?.absoluteString == "https://dns.quad9.net/dns-query")
        #expect(dns.servers == ["9.9.9.9", "149.112.112.112"])
        #expect(dns.matchDomains == [""], "every query goes to the tunnel's resolver")
    }

    @Test
    func withoutADoHURLTheNetworkSettingsArePlainDNS() throws {
        let plain = encrypted.replacingOccurrences(of: "DNSOverHTTPS = https://dns.quad9.net/dns-query\n", with: "")
        let configuration = try TunnelConfiguration(fromWgQuickConfig: plain, called: "WireGuard")

        let dns = try #require(networkSettings(for: configuration).dnsSettings)

        #expect(dns.dnsProtocol == .cleartext)
        #expect(dns.servers == ["9.9.9.9", "149.112.112.112"])
    }

    /// A backend node takes the settings' DNS configuration: its DoH URL, and its IPv6 servers with IPv6 tunnelled.
    @Test
    func theManagerBuildsTheNodeWithTheSettingsResolvers() throws {
        let manager = TunnelManager(
            settings: FakeTunnelSettings(dnsConfiguration: .adGuardFamily, networkOptions: TunnelNetworkOptions(ipv6: .tunnel)),
            configuration: try #require(TunnelEnvironment.configuration)
        )
        manager.attach(TunnelsService(tunnelProviders: [], store: FakeTunnelProfileStore(), clock: StepClock()))
        let node = WireGuardEndpoint(
            host: "203.0.113.10", port: 51820, clientAddress: "10.8.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
        )
        let credentials = ConnectionCredentials(
            nodeType: .wireguard, endpoint: .wireGuard(node), privateKey: "oK56DE9Ue9zHAt61A8xBeLjd9zLOUlGmk8hYB7sTf1k="
        )

        let interface = try manager.wireGuardConfiguration(from: credentials).interface

        #expect(interface.dns.map(\.stringRepresentation) == DNSConfiguration.adGuardFamily.servers)
        #expect(interface.dnsOverHTTPSURL == DNSConfiguration.adGuardFamily.dohURL)
    }

    private func networkSettings(for configuration: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        PacketTunnelSettingsGenerator(tunnelConfiguration: configuration, resolvedEndpoints: configuration.peers.map(\.endpoint))
            .generateNetworkSettings()
    }
}
