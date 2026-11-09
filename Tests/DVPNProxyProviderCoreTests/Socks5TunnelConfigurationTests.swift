//
//  Socks5TunnelConfigurationTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNProxyProviderCore
import Foundation
import Testing

/// hev-socks5-tunnel's configuration caps its sessions on iOS and tvOS, so many sessions at once cannot grow the
/// extension past iOS's memory limit; macOS, which has no such limit, gets none.
struct Socks5TunnelConfigurationTests {
    @Test
    func theMiscBlockCarriesTheSessionCap() throws {
        let configuration = ProxyPacketTunnelProvider.socks5TunnelConfiguration(
            mtu: 9000,
            proxy: LocalProxy(port: 1080, username: "user", password: "password")
        )

        let blocks = configuration.components(separatedBy: "\nmisc:\n")
        try #require(blocks.count == 2)
        let cap = "  max-session-count: \(ProxyPacketTunnelProvider.maxSessionCount)"
        #expect(blocks[1].components(separatedBy: "\n").contains(cap))
    }

    @Test
    func onlyMacOSGoesUncapped() {
        #expect(ProxyPacketTunnelProvider.sessionCap(onMacOS: false) == 100)
        #expect(ProxyPacketTunnelProvider.sessionCap(onMacOS: true) == 0)
    }
}
