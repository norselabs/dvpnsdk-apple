//
//  DNSConfigurationTests.swift
//  DVPNSDK
//

@testable import DVPNCoreKit
import Foundation
import NetworkExtension
import Testing

/// The resolvers a tunnel uses: the presets as their providers document them, the values apps stored before
/// `DNSConfiguration` existed, an app's own servers, and the DNS settings a tunnel applies.
struct DNSConfigurationTests {
    // MARK: Presets

    /// A preset's values as its provider's documentation gives them (see the presets' comment).
    struct Documented: Sendable, CustomTestStringConvertible {
        let preset: DNSConfiguration
        let name: String
        let servers: [String]
        let dohURL: String

        var testDescription: String { name }
    }

    static let documented = [
        Documented(
            preset: .cloudflare, name: "cloudflare",
            servers: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"],
            dohURL: "https://cloudflare-dns.com/dns-query"
        ),
        Documented(
            preset: .cloudflareMalwareBlocking, name: "cloudflare-security",
            servers: ["1.1.1.2", "1.0.0.2", "2606:4700:4700::1112", "2606:4700:4700::1002"],
            dohURL: "https://security.cloudflare-dns.com/dns-query"
        ),
        Documented(
            preset: .cloudflareFamily, name: "cloudflare-family",
            servers: ["1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"],
            dohURL: "https://family.cloudflare-dns.com/dns-query"
        ),
        Documented(
            preset: .quad9, name: "quad9",
            servers: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"],
            dohURL: "https://dns.quad9.net/dns-query"
        ),
        Documented(
            preset: .adGuard, name: "adguard",
            servers: ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"],
            dohURL: "https://dns.adguard-dns.com/dns-query"
        ),
        Documented(
            preset: .adGuardFamily, name: "adguard-family",
            servers: ["94.140.14.15", "94.140.15.16", "2a10:50c0::bad1:ff", "2a10:50c0::bad2:ff"],
            dohURL: "https://family.adguard-dns.com/dns-query"
        ),
        Documented(
            preset: .google, name: "google",
            servers: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"],
            dohURL: "https://dns.google/dns-query"
        ),
    ]

    /// A typo in a preset fails here.
    @Test(arguments: documented)
    func aPresetIsAsItsProviderDocumentsIt(_ documented: Documented) {
        #expect(documented.preset.name == documented.name)
        #expect(documented.preset.servers == documented.servers)
        #expect(documented.preset.dohURL?.absoluteString == documented.dohURL)
        #expect(documented.preset.isEncrypted)
    }

    @Test
    func everyPresetIsDocumented() {
        #expect(DNSConfiguration.presets == Self.documented.map(\.preset))
    }

    @Test
    func thePresetsAreDistinctAndLeaveOutMullvad() {
        #expect(Set(DNSConfiguration.presets.map(\.name)).count == DNSConfiguration.presets.count)
        #expect(!DNSConfiguration.presets.contains { $0.name.hasPrefix("mullvad") })
    }

    /// Mullvad's service (discontinued on 2 November 2026) is DoH only: every preset has its DoH URL.
    @Test
    func mullvadPresetsAreAsMullvadDocumentsThem() {
        let presets = [
            DNSConfiguration.Mullvad.unfiltered, .Mullvad.adBlock, .Mullvad.base, .Mullvad.extended, .Mullvad.family, .Mullvad.all,
        ]
        #expect(presets.map(\.name) == ["mullvad", "mullvad-adblock", "mullvad-base", "mullvad-extended", "mullvad-family", "mullvad-all"])
        #expect(presets.map(\.servers) == [2, 3, 4, 5, 6, 9].map { ["194.242.2.\($0)", "2a07:e340::\($0)"] })
        #expect(presets.compactMap(\.dohURL?.absoluteString) == [
            "https://dns.mullvad.net/dns-query",
            "https://adblock.dns.mullvad.net/dns-query",
            "https://base.dns.mullvad.net/dns-query",
            "https://extended.dns.mullvad.net/dns-query",
            "https://family.dns.mullvad.net/dns-query",
            "https://all.dns.mullvad.net/dns-query",
        ])
    }

    // MARK: DNSServerType

    @Test(arguments: DNSServerType.allCases)
    func aServerTypeIsItsServersInPlainDNS(_ type: DNSServerType) {
        #expect(type.configuration == DNSConfiguration(name: type.rawValue, servers: type.addresses))
        #expect(!type.configuration.isEncrypted)
    }

    /// What an app stored as a `DNSServerType` decodes as a `DNSConfiguration`.
    @Test(arguments: DNSServerType.allCases)
    func aStoredServerTypeDecodes(_ type: DNSServerType) throws {
        let stored = try JSONEncoder().encode(type)

        #expect(try JSONDecoder().decode(DNSConfiguration.self, from: stored) == type.configuration)
    }

    /// An app that implements only `selectedDNS` gets that provider's configuration.
    @Test
    func settingsWithAServerTypeOnlyGiveItsConfiguration() {
        final class LegacySettings: TunnelSettingsProviding {
            let selectedDNS: DNSServerType = .quad9
        }

        #expect(LegacySettings().dnsConfiguration == DNSServerType.quad9.configuration)
    }

    @Test
    func aConfigurationRoundTripsThroughCodable() throws {
        for configuration in DNSConfiguration.presets + [DNSConfiguration.quad9.unencrypted] {
            let decoded = try JSONDecoder().decode(DNSConfiguration.self, from: JSONEncoder().encode(configuration))
            #expect(decoded == configuration)
        }
    }

    // MARK: Custom

    @Test
    func aCustomConfigurationTakesIPAddressesAndAnHTTPSURL() throws {
        let custom = try #require(
            DNSConfiguration.custom(servers: [" 192.0.2.53", "2001:db8::53"], dohURL: URL(string: "https://dns.example/dns-query"))
        )

        #expect(custom.name == "custom")
        #expect(custom.servers == ["192.0.2.53", "2001:db8::53"])
        #expect(custom.isEncrypted)
    }

    @Test(arguments: [
        ["dns.example"],          // a host name, not an address
        ["2001:db8::53"],         // no IPv4 server, which every tunnel routes
        [String](),
    ])
    func aCustomConfigurationWithoutUsableServersIsRefused(_ servers: [String]) {
        #expect(DNSConfiguration.custom(servers: servers) == nil)
    }

    @Test
    func aCustomConfigurationWithAPlainHTTPURLIsRefused() {
        #expect(DNSConfiguration.custom(servers: ["192.0.2.53"], dohURL: URL(string: "http://dns.example/dns-query")) == nil)
    }

    // MARK: Tunnel settings

    @Test
    func ipv6ServersAreUsedOnlyWhenTheTunnelRoutesIPv6() {
        #expect(DNSConfiguration.quad9.servers(includingIPv6: false) == ["9.9.9.9", "149.112.112.112"])
        #expect(DNSConfiguration.quad9.servers(includingIPv6: true) == DNSConfiguration.quad9.servers)
    }

    /// With nothing usable left, the default provider answers rather than the network's resolvers.
    @Test
    func withNoUsableServerTheDefaultProvidersAreUsed() {
        let ipv6Only = DNSConfiguration(name: "v6", servers: ["2001:db8::53"])

        #expect(ipv6Only.servers(includingIPv6: false) == DNSServerType.default.addresses)
    }

    @Test
    func aDoHURLGivesEncryptedSettings() throws {
        let settings = DNSConfiguration.adGuardFamily.dnsSettings(includingIPv6: false)

        let encrypted = try #require(settings as? NEDNSOverHTTPSSettings)
        #expect(encrypted.dnsProtocol == .HTTPS)
        #expect(encrypted.serverURL?.absoluteString == "https://family.adguard-dns.com/dns-query")
        #expect(encrypted.servers == ["94.140.14.15", "94.140.15.16"])
    }

    @Test
    func withoutADoHURLTheSettingsArePlainDNS() {
        let settings = DNSConfiguration.adGuardFamily.unencrypted.dnsSettings(includingIPv6: true)

        #expect(!(settings is NEDNSOverHTTPSSettings))
        #expect(settings.dnsProtocol == .cleartext)
        #expect(settings.servers == DNSConfiguration.adGuardFamily.servers)
    }
}
