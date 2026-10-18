//
//  TunnelManagerRestartTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing
import WireGuardKit

/// `TunnelManager.restart()`: a WireGuard tunnel keeps everything but its resolvers, and with nothing stored to start
/// from the tunnel is left as it is.
@MainActor
struct TunnelManagerRestartTests {
    private let configuration = DVPNCoreConfiguration(
        appGroupID: "group.com.example.vpn.tests",
        protocols: [
            TunnelProtocolDescriptor(
                id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
            ),
            TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
        ]
    )

    init() {
        DVPNCore.bootstrap(configuration)
    }

    @Test
    func aWireGuardRestartChangesOnlyTheResolvers() throws {
        let stored = try TunnelConfiguration(
            fromWgQuickConfig: """
            [Interface]
            PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
            Address = 10.8.1.2/32
            DNS = 1.1.1.1, 1.0.0.1
            Jc = 4
            H1 = 1234567891

            [Peer]
            PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
            AllowedIPs = 0.0.0.0/0
            Endpoint = 203.0.113.10:51820
            PersistentKeepalive = 25
            """,
            called: "WireGuard"
        )

        let restarted = TunnelManager.configuration(stored, withDNS: DNSServerType.quad9.configuration, includingIPv6: false)

        #expect(restarted.interface.dns.map(\.stringRepresentation) == ["9.9.9.9", "149.112.112.112"])
        #expect(restarted.interface.dnsSearch.isEmpty)
        #expect(restarted.interface.dnsOverHTTPSURL == nil)
        var expected = stored.interface
        expected.dns = restarted.interface.dns
        #expect(restarted.interface == expected)
        #expect(restarted.peers == stored.peers)
        #expect(restarted.name == "WireGuard")
    }

    /// An encrypted preset gives the tunnel its DoH URL, and its IPv6 servers only when the tunnel routes IPv6.
    @Test
    func aWireGuardRestartTakesTheDoHURL() throws {
        let stored = try TunnelConfiguration(
            fromWgQuickConfig: """
            [Interface]
            PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
            Address = 10.8.1.2/32
            DNS = 1.1.1.1, 1.0.0.1

            [Peer]
            PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
            AllowedIPs = 0.0.0.0/0
            Endpoint = 203.0.113.10:51820
            """,
            called: "WireGuard"
        )

        let ipv4Only = TunnelManager.configuration(stored, withDNS: .cloudflareFamily, includingIPv6: false)
        let dualStack = TunnelManager.configuration(stored, withDNS: .cloudflareFamily, includingIPv6: true)

        #expect(ipv4Only.interface.dns.map(\.stringRepresentation) == ["1.1.1.3", "1.0.0.3"])
        #expect(ipv4Only.interface.dnsOverHTTPSURL?.absoluteString == "https://family.cloudflare-dns.com/dns-query")
        #expect(dualStack.interface.dns.map(\.stringRepresentation) == ["1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"])
        #expect(TunnelManager.configuration(stored, withDNS: DNSConfiguration.cloudflareFamily.unencrypted, includingIPv6: false)
            .interface.dnsOverHTTPSURL == nil)
    }

    @Test
    func withNoTunnelThereIsNothingToRestart() async {
        let manager = makeManager([])

        await #expect(throws: TunnelsServiceError.noStoredConfiguration) {
            try await manager.restart()
        }
    }

    /// A profile of an extension the app does not declare has no stored start this manager can read.
    @Test
    func aRunningTunnelWithNothingStoredIsLeftUp() async throws {
        let profile = FakeTunnelProfile(name: "Other", providerBundleID: "com.example.other-ne", status: .connected)
        profile.isOnDemandEnabled = true
        let manager = makeManager([profile])

        await #expect(throws: TunnelsServiceError.noStoredConfiguration) {
            try await manager.restart()
        }
        #expect(profile.stops == 0)
        #expect(profile.saves == 0)
        #expect(profile.isOnDemandEnabled)
    }

    /// A manager over a service of fake profiles that report their status changes to it.
    private func makeManager(_ profiles: [FakeTunnelProfile]) -> TunnelManager {
        let store = FakeTunnelProfileStore()
        store.profiles = profiles
        let service = TunnelsService(tunnelProviders: profiles, store: store, clock: StepClock())
        profiles.forEach { $0.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) } }
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: configuration)
        manager.attach(service)
        return manager
    }
}
