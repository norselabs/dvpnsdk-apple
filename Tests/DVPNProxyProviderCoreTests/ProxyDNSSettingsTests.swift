//
//  ProxyDNSSettingsTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNProxyProviderCore
import Foundation
import NetworkExtension
import Testing

/// The resolvers an Xray or Hysteria tunnel hands the system, from the addresses the app stored. The provider itself
/// cannot be made outside an extension, so the tests read what its settings take them from.
@Suite(.serialized)
struct ProxyDNSSettingsTests {
    /// One fixed suite, so a run leaves no new preferences file behind.
    private let suiteName = "com.example.vpn.tests.proxy-dns-settings"

    /// The tunnel's lookups go to the chosen provider over HTTPS, at one of its own addresses, for every name, and
    /// never fall back to plain DNS, which the node could read and answer.
    @Test(arguments: DNSServerType.allCases)
    func lookupsGoToTheProviderOverHTTPS(provider: DNSServerType) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ProxyPacketTunnelProvider.dnsSettings(servers: provider.addresses, in: defaults)

        let dns = try #require(settings as? NEDNSOverHTTPSSettings)
        #expect(dns.dnsProtocol == .HTTPS)
        #expect(dns.serverURL?.absoluteString == provider.dnsOverHTTPSURL(at: provider.addresses[0]))
        #expect(dns.servers == [provider.addresses[0]])
        #expect(dns.matchDomains == [""])
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            #expect(!dns.allowFailover)
        }
    }

    /// Settings an override of `makeNetworkSettings(network:)` builds itself, without DNS or with plain DNS of its
    /// own, still reach the system with the provider's DNS over HTTPS.
    @Test(arguments: [nil, ["203.0.113.53"]] as [[String]?])
    func settingsAnOverrideBuildsGetDNSOverHTTPS(overrideDNS: [String]?) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let built = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        built.dnsSettings = overrideDNS.map { NEDNSSettings(servers: $0) }

        let settings = ProxyPacketTunnelProvider.settingDNS(
            on: built, servers: DNSServerType.cloudflare.addresses, in: defaults
        )

        let dns = try #require(settings.dnsSettings as? NEDNSOverHTTPSSettings)
        #expect(dns.servers == [DNSServerType.cloudflare.addresses[0]])
    }

    /// Resolvers of no provider stay plain DNS, as before.
    @Test
    func otherResolversStayPlainDNS() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ProxyPacketTunnelProvider.dnsSettings(servers: ["203.0.113.53"], in: defaults)

        #expect(settings.dnsProtocol == .cleartext)
        #expect(settings.servers == ["203.0.113.53"])
        #expect(settings.matchDomains == nil)
    }
}
