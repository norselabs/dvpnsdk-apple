//
//  InterfaceConfigurationAmneziaWGTests.swift
//  DVPNSDK
//

@testable import DVPNWireGuardCore
import Foundation
import Testing
import WireGuardKitTypes

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
            "I1": "<b 0xf6ab3267fa><b 0xf6ab><t><r 10>", "I5": "<b 0x01>",
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
        #expect(interface.specialJunk1 == "<b 0xf6ab3267fa><b 0xf6ab><t><r 10>")
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

    /// An invalid value shows its key and length, never the value: the header protection key is a secret the node shares
    /// with its clients, and any other value is the node's text, which could read as lines of the log.
    @Test(arguments: ["HeaderProtectionKey", "headerprotectionkey", "S1", "I1"])
    func anInvalidValueShowsItsLengthOnly(key: String) {
        let error = AmneziaWGParameterError.invalidValue(key: key, value: "distinct\nkey")
        #expect(error.description == "Invalid value (12 characters) for AmneziaWG parameter '\(key)'")
    }

    // MARK: Node values

    /// A line break or control character in any value is refused: the configuration is stored as wg-quick text the
    /// extension reads back line by line, and handed to the engine as a C string, which a NUL cuts.
    @Test(arguments: [
        ("I1", "<b 0x01>\nDNS = 203.0.113.7"), ("I2", "<b 0x01>\r\nMTU = 1700"), ("I3", "<b 0x01>\u{2028}MTU = 1700"),
        ("I4", "<b 0x01>\u{2029}x"), ("I5", "<b 0x01>\u{85}x"), ("S1", "15\n"), ("H1", "1\u{0}"), ("H2", "1\tx"),
        ("Jc", "4\n"),
    ])
    func aLineBreakOrControlCharacterIsRefused(key: String, value: String) {
        var interface = interface
        #expect(throws: AmneziaWGParameterError.invalidValue(key: key, value: value)) { try interface.applyAmneziaWG([key: value]) }
    }

    /// T1 inverted: a node's I1 with line breaks no longer adds DNS, MTU or Address lines to the file the extension
    /// reads; without them, the value goes through and nothing else changes.
    @Test
    func aNodeCannotAddLinesToTheStoredFile() throws {
        let stored = try TunnelConfiguration(fromWgQuickConfig: """
        [Interface]
        PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
        Address = 10.10.0.2/32
        DNS = 1.1.1.1, 1.0.0.1

        [Peer]
        PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
        AllowedIPs = 0.0.0.0/0
        Endpoint = 192.0.2.10:51820
        """, called: "DVPN")
        let lines = "<b 0x01>\nDNS = 203.0.113.7\nMTU = 1700\nAddress = 192.168.1.77/24"
        #expect(throws: AmneziaWGParameterError.invalidValue(key: "I1", value: lines)) {
            try stored.applyingAmneziaWG(["I1": lines, "S1": "15", "H1": "1"])
        }

        let applied = try stored.applyingAmneziaWG(["I1": "<b 0x01>", "S1": "15", "H1": "1"])
        let reloaded = try WireGuardFileConfiguration(name: "DVPN", tunnelConfiguration: applied).toTunnelConfiguration()
        #expect(reloaded.interface.dns.map(\.stringRepresentation) == ["1.1.1.1", "1.0.0.1"])
        #expect(reloaded.interface.mtu == nil)
        #expect(reloaded.interface.addresses.map(\.stringRepresentation) == ["10.10.0.2/32"])
        #expect(reloaded.interface.specialJunk1 == "<b 0x01>")
    }

    /// S4 leaves room for a full packet in the engine's 1700-byte buffer on iOS and tvOS; past it, the engine panics
    /// on the first packet.
    @Test(arguments: [("0", true), ("388", true), ("389", false), ("1689", false), ("65535", false)])
    func s4LeavesRoomForAFullPacket(value: String, isAccepted: Bool) throws {
        var interface = interface
        if isAccepted {
            try interface.applyAmneziaWG(["S4": value])
            #expect(interface.transportPacketJunkSize == UInt16(value))
        } else {
            #expect(throws: AmneziaWGParameterError.invalidValue(key: "S4", value: value)) { try interface.applyAmneziaWG(["S4": value]) }
        }
    }

    /// An I-packet is tags the engine builds safely within one 1280-byte datagram.
    @Test(arguments: [
        "<b 0xf6ab3267fa><b 0xf6ab><t><r 10>", "<b F6AB>", "< b 0x01 > <t> <rc 5><rd 0>", "<t ignored>", "<r 1280>",
        "<b 0x01><r 1279>", "<r 1276><t>",
    ])
    func anIPacketTheEngineBuildsIsAccepted(value: String) throws {
        var interface = interface
        try interface.applyAmneziaWG(["I1": value])
        #expect(interface.specialJunk1 == value)
    }

    /// A negative or huge size, more than one datagram, a tag the engine does not know or one with no data to carry
    /// in an I-packet (`<d>`, `<ds>`, `<dz n>`), malformed hex, or text outside the tags is refused.
    @Test(arguments: [
        "<r -1>", "<rc -5>", "<rd -1>", "<r 1281>", "<r 99999999999999999999>", "<r 1276><t><b 0x01>", "<r x>", "<r>",
        "<c>", "<d>", "<ds>", "<dz 10>", "<dz -1>", "<b>", "<b 0x0>", "<b 0xzz>", "<b 0X01>", "<b 0x\u{FF11}\u{FF12}>",
        "<>", "<b 0x01", "x<b 0x01>", "<b 0x01>x",
    ])
    func anIPacketTheEngineCannotBuildSafelyIsRefused(value: String) {
        var interface = interface
        #expect(throws: AmneziaWGParameterError.invalidValue(key: "I1", value: value)) { try interface.applyAmneziaWG(["I1": value]) }
        #expect(interface.specialJunk1 == nil)
    }
}
