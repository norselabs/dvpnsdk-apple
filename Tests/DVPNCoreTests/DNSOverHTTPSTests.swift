//
//  DNSOverHTTPSTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import NetworkExtension
import Testing

/// Which provider a tunnel's stored resolvers belong to, and the DNS over HTTPS settings made from them. The tests
/// share one defaults suite, so they run one after the other.
@Suite(.serialized)
struct DNSOverHTTPSTests {
    /// One fixed suite, so a run leaves no new preferences file behind.
    private let suiteName = "com.example.vpn.tests.dns-over-https"

    @Test(arguments: [
        (DNSServerType.cloudflare, "1.0.0.1", "https://1.0.0.1/dns-query"),
        (DNSServerType.google, "8.8.4.4", "https://8.8.4.4/dns-query"),
        (DNSServerType.quad9, "149.112.112.112", "https://149.112.112.112/dns-query"),
    ])
    func eachAddressHasItsURL(provider: DNSServerType, address: String, url: String) {
        #expect(provider.dnsOverHTTPSURL(at: address) == url)
    }

    /// What the app stores for a provider, in any order, or one of its resolvers alone.
    @Test(arguments: DNSServerType.allCases)
    func aProvidersResolversNameIt(provider: DNSServerType) {
        #expect(DNSServerType(servers: provider.addresses) == provider)
        #expect(DNSServerType(servers: provider.addresses.reversed()) == provider)
        #expect(DNSServerType(servers: [provider.addresses[1]]) == provider)
    }

    /// No server, a server of no provider, and servers of two providers belong to none.
    @Test(arguments: [[], ["203.0.113.53"], ["1.1.1.1", "203.0.113.53"], ["1.1.1.1", "8.8.8.8"], ["1.1.1.1 "]])
    func otherServersNameNoProvider(servers: [String]) throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(DNSServerType(servers: servers) == nil)
        #expect(DNSServerType.dnsOverHTTPSSettings(servers: servers, in: defaults) == nil)
        #expect(defaults.string(forKey: DNSServerType.dnsOverHTTPSAddressKey) == nil)
    }

    /// The settings name one of the provider's addresses, whichever of them are stored, as the only server and as the
    /// URL's host; the first settings, and those after another provider's, name its first address.
    @Test
    func theSettingsNameOneOfTheProvidersAddresses() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = try #require(DNSServerType.dnsOverHTTPSSettings(servers: ["8.8.4.4"], in: defaults))
        #expect(first.servers == ["8.8.8.8"])
        #expect(first.serverURL?.absoluteString == "https://8.8.8.8/dns-query")
        #expect(first.matchDomains == [""])

        defaults.set("1.1.1.1", forKey: DNSServerType.dnsOverHTTPSAddressKey)
        let afterCloudflare = try #require(DNSServerType.dnsOverHTTPSSettings(servers: ["8.8.8.8", "8.8.4.4"], in: defaults))
        #expect(afterCloudflare.servers == ["8.8.8.8"])
    }

    /// Each settings name the provider's other address than the settings before: no two in a row share a host.
    @Test(arguments: DNSServerType.allCases)
    func noTwoSettingsInARowNameTheSameAddress(provider: DNSServerType) throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let hosts = try (0 ..< 4).map { _ in
            let settings = try #require(DNSServerType.dnsOverHTTPSSettings(servers: provider.addresses, in: defaults))
            #expect(settings.servers == [settings.serverURL?.host() ?? ""])
            return try #require(settings.serverURL?.host())
        }

        #expect(hosts == provider.addresses + provider.addresses)
    }

    private func freshDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
