//
//  DNSServerType+DNSOverHTTPS.swift
//  DVPNSDK
//

import Foundation
import NetworkExtension

// MARK: - DNS over HTTPS

package extension DNSServerType {
    /// A tunnel's DNS settings for `servers`, a provider's resolvers: every lookup the system's resolver makes goes to
    /// the provider over HTTPS, inside the tunnel, so the node can neither read nor answer it. `servers` are handed
    /// over as addresses, for the system to dial, and `allowFailover` (iOS, macOS and tvOS 26) is never set, so it
    /// keeps its default, off: with the provider out of reach names do not resolve, rather than fall back to the
    /// system's resolver. A program's own queries on port 53 are not the system resolver's: they stay plain DNS in
    /// the tunnel. Nil for servers that are not one provider's, which keep plain DNS.
    static func dnsOverHTTPSSettings(servers: [String]) -> NEDNSOverHTTPSSettings? {
        guard let provider = DNSServerType(servers: servers) else { return nil }
        let settings = NEDNSOverHTTPSSettings(servers: servers)
        settings.serverURL = URL(string: provider.dnsOverHTTPSURL)
        // Every name is the tunnel's to resolve.
        settings.matchDomains = [""]
        return settings
    }
}
