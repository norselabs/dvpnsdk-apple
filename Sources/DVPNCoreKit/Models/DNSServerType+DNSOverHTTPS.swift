//
//  DNSServerType+DNSOverHTTPS.swift
//  DVPNSDK
//

import Foundation
import NetworkExtension

// MARK: - DNS over HTTPS

package extension DNSServerType {
    /// App Group key: the address the last DNS over HTTPS settings named.
    static let dnsOverHTTPSAddressKey = "DNS_OVER_HTTPS_ADDRESS"

    /// A tunnel's DNS settings for `servers`, a provider's resolvers: every lookup the system's resolver makes goes to
    /// the provider over HTTPS, inside the tunnel, so the node can neither read nor answer it. Each call names one of
    /// the provider's addresses as the only server, for the system to dial, and as the URL's host: the address the
    /// call before did not name (kept in `defaults`; the first one after another provider's or none), so no two calls
    /// in a row share a host. Settings two calls apart name the same address. `allowFailover` (iOS,
    /// macOS and tvOS 26) is never set, so it keeps its default, off: with the provider out of reach names do not
    /// resolve, rather than fall back to the system's resolver. A program's own queries on port 53 are not the
    /// system resolver's: they stay plain DNS in the tunnel. Nil for servers that are not one provider's, which keep
    /// plain DNS.
    static func dnsOverHTTPSSettings(servers: [String], in defaults: UserDefaults = .shared) -> NEDNSOverHTTPSSettings? {
        guard let provider = DNSServerType(servers: servers) else { return nil }
        let addresses = provider.addresses
        let previous = defaults.string(forKey: dnsOverHTTPSAddressKey).flatMap(addresses.firstIndex(of:))
        let address = addresses[previous.map { ($0 + 1) % addresses.count } ?? 0]
        defaults.set(address, forKey: dnsOverHTTPSAddressKey)
        let settings = NEDNSOverHTTPSSettings(servers: [address])
        settings.serverURL = URL(string: provider.dnsOverHTTPSURL(at: address))
        // Every name is the tunnel's to resolve.
        settings.matchDomains = [""]
        return settings
    }
}
