//
//  Socks5TunnelConfigurationTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNProxyProviderCore
import Foundation
import Testing

/// hev-socks5-tunnel's configuration caps its sessions on iOS and tvOS, so many sessions at once cannot grow the
/// extension past iOS's memory limit, and ends a quiet UDP association there after 15 s; macOS, which has no such limit,
/// gets no cap and a quiet minute.
struct Socks5TunnelConfigurationTests {
    @Test
    func theMiscBlockCarriesTheSessionCap() throws {
        let configuration = ProxyPacketTunnelProvider.socks5TunnelConfiguration(
            mtu: 9000,
            proxy: LocalProxy(port: 1080, username: "user", password: "password")
        )

        let blocks = configuration.components(separatedBy: "\nmisc:\n")
        try #require(blocks.count == 2)
        let lines = blocks[1].components(separatedBy: "\n")
        let cap = ProxyPacketTunnelProvider.maxSessionCount
        #expect(lines.contains("  max-session-count: \(cap)"))
        let udpTimeout = ProxyPacketTunnelProvider.udpReadWriteTimeout(sessionCap: cap)
        #expect(lines.contains("  udp-read-write-timeout: \(udpTimeout)"))
    }

    @Test
    func onlyMacOSGoesUncapped() {
        #expect(ProxyPacketTunnelProvider.sessionCap(onMacOS: false) == 100)
        #expect(ProxyPacketTunnelProvider.sessionCap(onMacOS: true) == 0)
    }

    @Test
    func aCapShortensTheQuietUDPAssociation() {
        #expect(ProxyPacketTunnelProvider.udpReadWriteTimeout(sessionCap: 100) == 15000)
        #expect(ProxyPacketTunnelProvider.udpReadWriteTimeout(sessionCap: 0) == 60000)
    }
}
