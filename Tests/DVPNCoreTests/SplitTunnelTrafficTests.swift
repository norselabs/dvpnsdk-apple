//
//  SplitTunnelTrafficTests.swift
//  DVPNCore
//

import DVPNSplitTunnelCore
import Foundation
import Testing

/// What the split-tunnel proxy is offered and what it never sees.
struct SplitTunnelTrafficTests {
    /// The system's DHCP never reaches the proxy: its renewals share one socket that a proxy which stops or dies
    /// would take down with it.
    @Test(arguments: [UInt16(67), 68, 546, 547])
    func dhcpIsLeftOut(port: UInt16) {
        #expect(SplitTunnelTraffic.excluded.contains { $0.port == port && $0.isUDPOnly && $0.prefix == 0 })
    }

    @Test(arguments: [
        ("10.0.0.0", 8), ("172.16.0.0", 12), ("192.168.0.0", 16), ("169.254.0.0", 16), ("224.0.0.0", 4),
        ("255.255.255.255", 32), ("fc00::", 7), ("fe80::", 10), ("ff00::", 8),
    ])
    func theLocalNetworkIsLeftOut(address: String, prefix: Int) {
        #expect(SplitTunnelTraffic.excluded.contains { $0.address == address && $0.prefix == prefix && $0.port == nil })
    }

    /// Every address of both families is offered, and only an exclusion that names a port uses a wildcard address,
    /// as the system requires.
    @Test
    func everythingElseIsOffered() {
        #expect(SplitTunnelTraffic.offered.map(\.prefix) == [0, 0])
        #expect(SplitTunnelTraffic.excluded.filter { $0.address == "0.0.0.0" || $0.address == "::" }.allSatisfy { $0.port != nil })
    }

    /// The tunnel's own traffic to its node never reaches the proxy, whatever its port and protocol.
    @Test
    func theNodeIsLeftOut() {
        let excluded = SplitTunnelTraffic.excluded(node: ["203.0.113.7", "2001:db8::7", "node.example", ""])
        #expect(excluded.map { "\($0.address)/\($0.prefix)" } == ["203.0.113.7/32", "2001:db8::7/128"])
        #expect(excluded.allSatisfy { $0.port == nil && !$0.isUDPOnly })
    }

    @Test
    func aMessageRoundTrips() {
        #expect(SplitTunnelMessage(data: SplitTunnelMessage.reloadSettings.data) == .reloadSettings)
        #expect(SplitTunnelMessage(data: Data([0])) == nil)
        #expect(SplitTunnelMessage(data: Data()) == nil)
    }
}
