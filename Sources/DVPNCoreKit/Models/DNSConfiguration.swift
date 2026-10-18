//
//  DNSConfiguration.swift
//  DVPNSDK
//

import Darwin
import Foundation
import NetworkExtension

// MARK: - DNSConfiguration

/// The resolvers a tunnel gives the system: DNS servers and, optionally, the DNS-over-HTTPS endpoint they serve.
///
/// With `dohURL` the system sends every query to that URL over HTTPS (`NEDNSOverHTTPSSettings`), reaching it at
/// `servers`, so the node the tunnel goes through sees neither the names looked up nor the answers. Without it the
/// servers answer plain DNS, inside the tunnel. The presets carry their provider's DoH URL; `unencrypted` drops it for
/// plain DNS at the same servers.
///
/// It generalises `DNSServerType`, which stays for the apps that store it: `DNSServerType.configuration` and a stored
/// `DNSServerType` value decoded as a `DNSConfiguration` are that provider's IPv4 servers in plain DNS, as the SDK
/// always used them.
public struct DNSConfiguration: Hashable, Sendable {
    /// What the configuration is, for an app to tell configurations apart and remember its user's choice; not text to
    /// show (the SDK writes none). A preset's is its provider and filter (`cloudflare`, `cloudflare-family`, …), a
    /// `DNSServerType`'s its raw value.
    public let name: String
    /// IPv4 and IPv6 addresses, in the order the system should try them. A tunnel uses the IPv6 ones only when IPv6
    /// goes through it (`TunnelNetworkOptions.ipv6`): otherwise the system would reach them around the tunnel.
    public let servers: [String]
    /// The DNS-over-HTTPS (RFC 8484) endpoint, `https://…/dns-query`, served at `servers`; nil for plain DNS.
    public let dohURL: URL?

    public init(name: String, servers: [String], dohURL: URL? = nil) {
        self.name = name
        self.servers = servers
        self.dohURL = dohURL
    }
}

// MARK: - Custom

public extension DNSConfiguration {
    /// A configuration of the app's own, nil when it cannot work: every server must be an IP address and at least one
    /// an IPv4 address (a tunnel always routes IPv4, IPv6 only with `ipv6: .tunnel`), and `dohURL` an `https` URL.
    static func custom(name: String = "custom", servers: [String], dohURL: URL? = nil) -> DNSConfiguration? {
        let servers = servers.map { $0.trimmingCharacters(in: .whitespaces) }
        guard servers.contains(where: { IPFamily(of: $0) == .v4 }),
              servers.allSatisfy({ IPFamily(of: $0) != nil })
        else { return nil }
        if let dohURL, !Self.isUsableDoHURL(dohURL) { return nil }
        return DNSConfiguration(name: name, servers: servers, dohURL: dohURL)
    }

    /// The same servers in plain DNS.
    var unencrypted: DNSConfiguration {
        DNSConfiguration(name: name, servers: servers, dohURL: nil)
    }

    /// Whether a tunnel asks these resolvers over HTTPS.
    var isEncrypted: Bool {
        dohURL.map(Self.isUsableDoHURL) ?? false
    }
}

// MARK: - Tunnel settings

public extension DNSConfiguration {
    /// The servers a tunnel gives the system: the IP addresses among `servers`, the IPv6 ones only when the tunnel
    /// routes IPv6 (`includingIPv6`). When none would be left, `DNSServerType.default`'s, so that DNS never falls to the
    /// network's resolvers.
    func servers(includingIPv6: Bool) -> [String] {
        let usable = servers.filter { server in
            switch IPFamily(of: server) {
            case .v4: return true
            case .v6: return includingIPv6
            case nil: return false
            }
        }
        return usable.isEmpty ? DNSServerType.default.addresses : usable
    }

    /// A tunnel's DNS settings: DNS over HTTPS when `dohURL` is a usable HTTPS URL, plain DNS at the same servers
    /// otherwise. The system's own failover (`allowFailover`) stays off: it would fall back to the network's resolver,
    /// outside the tunnel.
    func dnsSettings(includingIPv6: Bool) -> NEDNSSettings {
        let servers = servers(includingIPv6: includingIPv6)
        guard let dohURL, Self.isUsableDoHURL(dohURL) else { return NEDNSSettings(servers: servers) }
        let settings = NEDNSOverHTTPSSettings(servers: servers)
        settings.serverURL = dohURL
        return settings
    }
}

// MARK: - Presets

/// Each provider's addresses and DoH endpoint as its own documentation gives them (checked October 2026): Cloudflare
/// <https://developers.cloudflare.com/1.1.1.1/infrastructure/network-operators/>, Quad9
/// <https://www.quad9.net/service/service-addresses-and-features>, AdGuard
/// <https://adguard-dns.io/kb/general/dns-providers/>, Google <https://developers.google.com/speed/public-dns/docs/using>
/// and <https://developers.google.com/speed/public-dns/docs/doh>, Mullvad
/// <https://mullvad.net/en/help/dns-over-https-and-dns-over-tls>.
public extension DNSConfiguration {
    /// Cloudflare 1.1.1.1, unfiltered.
    static let cloudflare = DNSConfiguration(
        name: "cloudflare",
        servers: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"],
        dohURL: URL(string: "https://cloudflare-dns.com/dns-query")
    )

    /// 1.1.1.1 for Families: malware blocked.
    static let cloudflareMalwareBlocking = DNSConfiguration(
        name: "cloudflare-security",
        servers: ["1.1.1.2", "1.0.0.2", "2606:4700:4700::1112", "2606:4700:4700::1002"],
        dohURL: URL(string: "https://security.cloudflare-dns.com/dns-query")
    )

    /// 1.1.1.1 for Families: malware and adult content blocked.
    static let cloudflareFamily = DNSConfiguration(
        name: "cloudflare-family",
        servers: ["1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"],
        dohURL: URL(string: "https://family.cloudflare-dns.com/dns-query")
    )

    /// Quad9, its recommended service: malware blocked, DNSSEC validated.
    static let quad9 = DNSConfiguration(
        name: "quad9",
        servers: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"],
        dohURL: URL(string: "https://dns.quad9.net/dns-query")
    )

    /// AdGuard DNS, default servers: ads and trackers blocked.
    static let adGuard = DNSConfiguration(
        name: "adguard",
        servers: ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"],
        dohURL: URL(string: "https://dns.adguard-dns.com/dns-query")
    )

    /// AdGuard DNS family protection: the default servers' blocking plus adult content, and safe search.
    static let adGuardFamily = DNSConfiguration(
        name: "adguard-family",
        servers: ["94.140.14.15", "94.140.15.16", "2a10:50c0::bad1:ff", "2a10:50c0::bad2:ff"],
        dohURL: URL(string: "https://family.adguard-dns.com/dns-query")
    )

    /// Google Public DNS, unfiltered.
    static let google = DNSConfiguration(
        name: "google",
        servers: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"],
        dohURL: URL(string: "https://dns.google/dns-query")
    )

    /// The presets an app can offer, in this order. The Mullvad ones are left out: that service ends on 2 November 2026.
    static let presets: [DNSConfiguration] = [
        .cloudflare, .cloudflareMalwareBlocking, .cloudflareFamily, .quad9, .adGuard, .adGuardFamily, .google,
    ]
}

// MARK: - Mullvad (discontinued)

/// Mullvad's public encrypted DNS. It answers DNS over HTTPS and over TLS only, so these presets have no plain DNS
/// (`unencrypted` would not resolve). Mullvad discontinues the service on 2 November 2026 and recommends Quad9
/// instead (<https://mullvad.net/en/blog/2026/9/3/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead>);
/// DNS for Mullvad VPN's own customers is not affected.
public extension DNSConfiguration {
    @available(*, deprecated, message: "Mullvad's public encrypted DNS ends on 2 November 2026; use quad9.")
    static var mullvad: DNSConfiguration { Mullvad.unfiltered }

    /// Ads and trackers blocked.
    @available(*, deprecated, message: "Mullvad's public encrypted DNS ends on 2 November 2026; use adGuard.")
    static var mullvadAdBlock: DNSConfiguration { Mullvad.adBlock }

    /// Ads, trackers and malware blocked.
    @available(*, deprecated, message: "Mullvad's public encrypted DNS ends on 2 November 2026; use adGuard or quad9.")
    static var mullvadBase: DNSConfiguration { Mullvad.base }

    /// Ads, trackers, malware and social media blocked.
    @available(*, deprecated, message: "Mullvad's public encrypted DNS ends on 2 November 2026.")
    static var mullvadExtended: DNSConfiguration { Mullvad.extended }

    /// Ads, trackers, malware, adult content and gambling blocked.
    @available(*, deprecated, message: "Mullvad's public encrypted DNS ends on 2 November 2026; use adGuardFamily or cloudflareFamily.")
    static var mullvadFamily: DNSConfiguration { Mullvad.family }

    /// Ads, trackers, malware, adult content, gambling and social media blocked.
    @available(*, deprecated, message: "Mullvad's public encrypted DNS ends on 2 November 2026.")
    static var mullvadAll: DNSConfiguration { Mullvad.all }
}

extension DNSConfiguration {
    /// The Mullvad presets, held here so that the deprecated accessors are their only public face.
    enum Mullvad {
        static let unfiltered = DNSConfiguration(
            name: "mullvad", servers: ["194.242.2.2", "2a07:e340::2"], dohURL: URL(string: "https://dns.mullvad.net/dns-query")
        )
        static let adBlock = DNSConfiguration(
            name: "mullvad-adblock", servers: ["194.242.2.3", "2a07:e340::3"], dohURL: URL(string: "https://adblock.dns.mullvad.net/dns-query")
        )
        static let base = DNSConfiguration(
            name: "mullvad-base", servers: ["194.242.2.4", "2a07:e340::4"], dohURL: URL(string: "https://base.dns.mullvad.net/dns-query")
        )
        static let extended = DNSConfiguration(
            name: "mullvad-extended", servers: ["194.242.2.5", "2a07:e340::5"], dohURL: URL(string: "https://extended.dns.mullvad.net/dns-query")
        )
        static let family = DNSConfiguration(
            name: "mullvad-family", servers: ["194.242.2.6", "2a07:e340::6"], dohURL: URL(string: "https://family.dns.mullvad.net/dns-query")
        )
        static let all = DNSConfiguration(
            name: "mullvad-all", servers: ["194.242.2.9", "2a07:e340::9"], dohURL: URL(string: "https://all.dns.mullvad.net/dns-query")
        )
    }
}

// MARK: - DNSServerType

public extension DNSServerType {
    /// This provider as the SDK always used it: its IPv4 servers in plain DNS.
    var configuration: DNSConfiguration {
        DNSConfiguration(name: rawValue, servers: addresses)
    }
}

// MARK: - Codable

extension DNSConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, servers, dohURL
    }

    /// Also reads a `DNSServerType` an app stored before this type existed (its raw value), as that provider's
    /// `configuration`.
    public init(from decoder: any Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(DNSServerType.self) {
            self = legacy.configuration
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            servers: try container.decode([String].self, forKey: .servers),
            dohURL: try container.decodeIfPresent(URL.self, forKey: .dohURL)
        )
    }
}

// MARK: - Private

private extension DNSConfiguration {
    enum IPFamily {
        case v4
        case v6

        init?(of address: String) {
            var ipv4 = in_addr()
            var ipv6 = in6_addr()
            if inet_pton(AF_INET, address, &ipv4) == 1 {
                self = .v4
            } else if inet_pton(AF_INET6, address, &ipv6) == 1 {
                self = .v6
            } else {
                return nil
            }
        }
    }

    static func isUsableDoHURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host() ?? "").isEmpty
    }
}
