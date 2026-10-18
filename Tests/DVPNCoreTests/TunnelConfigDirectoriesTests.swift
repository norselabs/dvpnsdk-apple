//
//  TunnelConfigDirectoriesTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import Testing

/// The DNS hand-over between the app, which writes it, and the proxy extensions, which read it.
///
/// One fixed suite, emptied before and after each test, so the tests run one at a time: a suite per test left
/// an empty preferences file behind on every run, since `removePersistentDomain` keeps the file.
@Suite(.serialized)
struct TunnelConfigDirectoriesTests {
    private let suiteName = "com.example.vpn.tests.dns"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test(arguments: DNSServerType.allCases)
    func storedProviderIsReadBack(_ provider: DNSServerType) {
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TunnelConfigDirectories.storeDNS(provider, in: defaults)

        #expect(TunnelConfigDirectories.dns(in: defaults) == provider.addresses)
    }

    @Test
    func commaSeparatedStringFromEarlierBuildsIsSplit() {
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("9.9.9.9, 149.112.112.112", forKey: TunnelConfigDirectories.dnsKey)

        #expect(TunnelConfigDirectories.dns(in: defaults) == ["9.9.9.9", "149.112.112.112"])
    }

    @Test
    func nothingStoredFallsBackToTheDefaultProvider() {
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(TunnelConfigDirectories.dns(in: defaults) == ["1.1.1.1", "1.0.0.1"])
    }

    @Test
    func aStoredNetworkIsReadBack() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = NetworkModel(hideVPNIcon: false, ipv6Enabled: true)

        TunnelConfigDirectories.storeNetwork(network, in: defaults)

        #expect(TunnelConfigDirectories.network(in: defaults) == network)
    }

    /// What a proxy extension finds when the app that started it predates the stored network: IPv6 left out.
    @Test
    func withNoNetworkStoredTheDefaultApplies() {
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(TunnelConfigDirectories.network(in: defaults) == .default)
    }
}
