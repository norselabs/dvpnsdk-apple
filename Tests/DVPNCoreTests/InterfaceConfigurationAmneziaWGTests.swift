//
//  InterfaceConfigurationAmneziaWGTests.swift
//  DVPNCore
//

@testable import DVPNWireGuardCore
import Foundation
import Testing
import WireGuardKit

struct InterfaceConfigurationAmneziaWGTests {
    private var interface: InterfaceConfiguration {
        InterfaceConfiguration(privateKey: PrivateKey(base64Key: "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=")!)
    }

    @Test
    func appliesVersionOneParametersCaseInsensitively() throws {
        var interface = interface
        try interface.applyAmneziaWG([
            "jc": "4", "JMIN": "40", "Jmax": "70",
            "S1": "15", "s2": "18", "S3": "0", "S4": "12",
            "H1": "1234567", "H2": "2345678", "H3": "3456789", "H4": "4567890",
            "I1": "<b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>", "I5": "<b 0x01>",
        ])

        #expect(interface.junkPacketCount == 4)
        #expect(interface.junkPacketMinSize == 40)
        #expect(interface.junkPacketMaxSize == 70)
        #expect(interface.initPacketJunkSize == 15)
        #expect(interface.responsePacketJunkSize == 18)
        #expect(interface.cookieReplyPacketJunkSize == 0)
        #expect(interface.transportPacketJunkSize == 12)
        #expect(interface.initPacketMagicHeader == "1234567")
        #expect(interface.transportPacketMagicHeader == "4567890")
        #expect(interface.specialJunk1 == "<b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>")
        #expect(interface.specialJunk5 == "<b 0x01>")
        #expect(interface.hasAmneziaWGParameters)
    }

    @Test
    func appliesVersionTwoParameters() throws {
        var interface = interface
        try interface.applyAmneziaWG([
            "H1": "100-200",
            "HeaderProtectionKey": "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=",
            "ContentPaddingAddition": "16",
            "RekeyAfterTime": "120s",
            "RandomTrailers": "on",
            "DisableCookies": "true",
        ])

        #expect(interface.initPacketMagicHeader == "100-200")
        #expect(interface.headerProtectionKey?.base64Key == "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=")
        #expect(interface.contentPaddingAddition == "16")
        #expect(interface.rekeyAfterTime == "120s")
        #expect(interface.randomTrailers == "on")
        #expect(interface.disableCookies == "true")
    }

    @Test
    func rejectsInvalidValuesAndUnknownKeys() {
        var interface = interface
        #expect(throws: AmneziaWGParameterError.invalidValue(key: "Jc", value: "abc")) { try interface.applyAmneziaWG(["Jc": "abc"]) }
        #expect(throws: (any Error).self) { try interface.applyAmneziaWG(["Jmin": "70000"]) }
        #expect(throws: (any Error).self) { try interface.applyAmneziaWG(["H1": "  "]) }
        #expect(throws: (any Error).self) { try interface.applyAmneziaWG(["HeaderProtectionKey": "not-a-key"]) }
        #expect(throws: AmneziaWGParameterError.unrecognizedKey("PrivateKey")) { try interface.applyAmneziaWG(["PrivateKey": "x"]) }
        #expect(!interface.hasAmneziaWGParameters)
    }

    @Test
    func applyingToTunnelConfiguration() throws {
        let peer = PeerConfiguration(publicKey: PrivateKey().publicKey)
        let plain = TunnelConfiguration(name: "WireGuard", interface: interface, peers: [peer])

        #expect(try plain.applyingAmneziaWG([:]) === plain)

        let amnezia = try plain.applyingAmneziaWG(["Jc": "3", "Jmin": "10", "Jmax": "50"])
        #expect(amnezia.hasAmneziaWGParameters)
        #expect(!plain.hasAmneziaWGParameters)
        #expect(amnezia.name == "WireGuard")
        #expect(amnezia.peers.map(\.publicKey) == [peer.publicKey])
        #expect(amnezia.asWgQuickConfig().contains("Jc = 3"))
    }

    // MARK: Junk defaults

    @Test
    func junkDefaultsFillOnlyMissingKeys() {
        let node = ["S1": "15", "S2": "18", "S3": "0", "S4": "7", "H1": "1234567891", "H2": "1234567892", "H3": "1234567893", "H4": "1234567894"]
        let filled = AmneziaWGJunkDefaults.filling(node)
        #expect(filled["Jc"] == "4")
        #expect(filled["Jmin"] == "64")
        #expect(filled["Jmax"] == "256")
        #expect(filled["H1"] == "1234567891")

        #expect(AmneziaWGJunkDefaults.filling(["jc": "9", "S1": "1"])["jc"] == "9", "an explicit value wins, whatever its case")
        #expect(AmneziaWGJunkDefaults.filling(["jc": "9", "S1": "1"])["Jc"] == nil)
        #expect(AmneziaWGJunkDefaults.filling([:]) == [:], "plain WireGuard stays plain")
    }

    @Test
    func nodeParametersProduceAnAmneziaWGInterface() throws {
        var interface = InterfaceConfiguration(privateKey: PrivateKey())
        let node = [
            "S1": "15", "S2": "18", "S3": "0", "S4": "7",
            "H1": "1234567891", "H2": "1234567892", "H3": "1234567893", "H4": "1234567894",
            "I1": "<b 0xf6ab><r 10>",
        ]
        try interface.applyAmneziaWG(AmneziaWGJunkDefaults.filling(node))
        #expect(interface.hasAmneziaWGParameters)
        #expect(interface.junkPacketCount == 4)
        #expect(interface.initPacketJunkSize == 15)
        #expect(interface.initPacketMagicHeader == "1234567891")
        #expect(interface.specialJunk1 == "<b 0xf6ab><r 10>")
    }
}
