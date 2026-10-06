//
//  WireGuardConfigTests.swift
//  DVPNCore
//

@testable import DVPNWireGuardCore
import Foundation
import Testing
import WireGuardKit

struct WireGuardConfigTests {
    private let sampleConfig = """
    [Interface]
    PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
    Address = 10.10.0.2/32
    DNS = 8.8.8.8, 1.1.1.1
    MTU = 1420

    [Peer]
    PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
    AllowedIPs = 0.0.0.0/0
    Endpoint = 192.0.2.10:51820
    PersistentKeepalive = 25
    """

    private let amneziaConfig = """
    [Interface]
    PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
    Address = 10.10.0.2/32
    DNS = 1.1.1.1
    Jc = 4
    Jmin = 40
    Jmax = 70
    S1 = 15
    S2 = 18
    H1 = 1234567890
    H2 = 987654321
    H3 = 111111111
    H4 = 222222222
    I1 = <b 0xf6ab3267fa><r 10>

    [Peer]
    PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
    AllowedIPs = 0.0.0.0/0
    Endpoint = 192.0.2.10:51820
    PersistentKeepalive = 25
    """

    @Test
    func parseWireGuardConfig() throws {
        let configuration = try TunnelConfiguration(fromWgQuickConfig: sampleConfig, called: "Test")

        #expect(configuration.name == "Test")
        #expect(configuration.interface.addresses.map(\.stringRepresentation) == ["10.10.0.2/32"])
        #expect(configuration.interface.dns.map(\.stringRepresentation) == ["8.8.8.8", "1.1.1.1"])
        #expect(configuration.interface.mtu == 1420)
        #expect(configuration.peers.count == 1)
        #expect(configuration.peers[0].endpoint?.stringRepresentation == "192.0.2.10:51820")
        #expect(configuration.peers[0].persistentKeepAlive == "25")
        #expect(configuration.peers[0].allowedIPs.map(\.stringRepresentation) == ["0.0.0.0/0"])
        #expect(!configuration.hasAmneziaWGParameters)
    }

    @Test
    func serializeParseRoundTrip() throws {
        let original = try TunnelConfiguration(fromWgQuickConfig: sampleConfig, called: "Test")
        let serialized = original.asWgQuickConfig()
        let reparsed = try TunnelConfiguration(fromWgQuickConfig: serialized, called: "Test")

        #expect(reparsed.interface.privateKey == original.interface.privateKey)
        #expect(reparsed.interface.addresses == original.interface.addresses)
        #expect(reparsed.interface.dns == original.interface.dns)
        #expect(reparsed.interface.mtu == original.interface.mtu)
        #expect(reparsed.peers.map(\.publicKey) == original.peers.map(\.publicKey))
        #expect(reparsed.peers.map(\.endpoint) == original.peers.map(\.endpoint))
        #expect(reparsed.peers.map(\.persistentKeepAlive) == original.peers.map(\.persistentKeepAlive))
        #expect(!serialized.contains("Jc = "))
    }

    @Test
    func parseRejectsUnknownInterfaceKey() {
        let broken = """
        [Interface]
        PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
        Bogus = value
        """
        #expect(throws: (any Error).self) { try TunnelConfiguration(fromWgQuickConfig: broken) }
    }

    // MARK: AmneziaWG through the same parser and storage envelope

    @Test
    func amneziaWGConfigRoundTripsThroughFileEnvelope() throws {
        let configuration = try TunnelConfiguration(fromWgQuickConfig: amneziaConfig, called: "AmneziaWG")
        #expect(configuration.hasAmneziaWGParameters)
        #expect(configuration.interface.junkPacketCount == 4)
        #expect(configuration.interface.initPacketJunkSize == 15)
        #expect(configuration.interface.transportPacketMagicHeader == "222222222")
        #expect(configuration.interface.specialJunk1 == "<b 0xf6ab3267fa><r 10>")

        let envelope = WireGuardFileConfiguration(name: "AmneziaWG", tunnelConfiguration: configuration)
        #expect(envelope.wireGuardConfig.contains("Jc = 4"))
        #expect(envelope.wireGuardConfig.contains("H1 = 1234567890"))

        let reloaded = try envelope.toTunnelConfiguration()
        #expect(reloaded.interface == configuration.interface)
        #expect(reloaded.peers.map(\.publicKey) == configuration.peers.map(\.publicKey))
    }

    @Test
    func fileEnvelopeCodableKeepsTheStoredText() throws {
        let configuration = try TunnelConfiguration(fromWgQuickConfig: amneziaConfig, called: "AmneziaWG")
        let envelope = WireGuardFileConfiguration(name: "AmneziaWG", tunnelConfiguration: configuration)
        let decoded = try JSONDecoder().decode(WireGuardFileConfiguration.self, from: JSONEncoder().encode(envelope))
        #expect(decoded.wireGuardConfig == envelope.wireGuardConfig)
        #expect(decoded.name == "AmneziaWG")
    }
}
