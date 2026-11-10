//
//  DNSOverHTTPSTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import NetworkExtension
import Testing

/// Which provider a tunnel's stored resolvers belong to, and the DNS over HTTPS settings made from them.
struct DNSOverHTTPSTests {
    @Test(arguments: [
        (DNSServerType.cloudflare, "https://1.1.1.1/dns-query"),
        (DNSServerType.google, "https://8.8.8.8/dns-query"),
        (DNSServerType.quad9, "https://9.9.9.9/dns-query"),
    ])
    func eachProviderHasItsURL(provider: DNSServerType, url: String) {
        #expect(provider.dnsOverHTTPSURL == url)
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
    func otherServersNameNoProvider(servers: [String]) {
        #expect(DNSServerType(servers: servers) == nil)
        #expect(DNSServerType.dnsOverHTTPSSettings(servers: servers) == nil)
    }

    /// The settings carry the stored servers as they are, for the system to dial; the URL names the provider's first
    /// resolver, whichever of them is stored.
    @Test
    func theSettingsDialTheStoredServers() throws {
        let settings = try #require(DNSServerType.dnsOverHTTPSSettings(servers: ["8.8.4.4"]))

        #expect(settings.servers == ["8.8.4.4"])
        #expect(settings.serverURL?.absoluteString == "https://8.8.8.8/dns-query")
        #expect(settings.matchDomains == [""])
    }
}
