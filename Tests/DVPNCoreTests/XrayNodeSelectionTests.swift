//
//  XrayNodeSelectionTests.swift
//  DVPNSDK
//

import DVPNSDK
@testable import DVPNTunnel
@testable import DVPNXRayCore
import Foundation
import Testing

struct XrayNodeSelectionTests {
    private let uuid = "11111111-2222-3333-4444-555555555555"
    private let reality = XrayInbound.Reality(
        serverName: "www.apple.com", shortID: "0123456789abcdef", publicKey: "SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", fingerprint: "chrome"
    )
    private let pin = "abababababababababababababababababababababababababababababababab"

    /// The shape of a production node: five inbounds, the VLESS+REALITY+Vision one over RAW wins.
    @Test
    func prefersVLESSRealityVisionOverRaw() throws {
        let node = XrayNodeEndpoint(host: "203.0.113.5", inbounds: [
            XrayInbound(port: 28214, proxyProtocol: .vmess, transport: .websocket, security: .tls, tlsPin: pin),
            XrayInbound(port: 13824, proxyProtocol: .vmess, transport: .xhttp, security: .tls, tlsPin: pin),
            XrayInbound(port: 32574, proxyProtocol: .vmess, transport: .xhttp, security: .reality, reality: reality),
            XrayInbound(port: 7015, proxyProtocol: .vless, transport: .xhttp, security: .reality, reality: reality),
            XrayInbound(port: 38808, proxyProtocol: .vless, transport: .tcp, security: .reality, flow: .vision, reality: reality),
        ])
        let model = try XrayNodeSelection.model(for: node, uuid: uuid)

        #expect(model.outbound == .vless(VLESS(address: "203.0.113.5", port: 38808, users: [VLESS.User(id: uuid, flow: .xtlsRprxVision)])))
        #expect(model.transport == .tcp(.init()))
        #expect(
            model.security ==
                .reality(StreamSettings.Reality(fingerprint: .chrome, serverName: "www.apple.com", publicKey: reality.publicKey, shortId: reality.shortID))
        )

        let stream = try #require(try model.proxyOutbound()["streamSettings"] as? [String: Any])
        #expect(stream["security"] as? String == "reality")
        #expect((stream["realitySettings"] as? [String: Any])?["publicKey"] as? String == reality.publicKey)
    }

    @Test
    func tlsInboundIsPinnedAndTrojanUsesTheUUID() throws {
        let node = XrayNodeEndpoint(host: "h", inbounds: [
            XrayInbound(port: 1, proxyProtocol: .trojan, transport: .grpc, security: .tls, tlsPin: pin),
            XrayInbound(port: 2, proxyProtocol: .vless, transport: .tcp, security: .none),
        ])
        let model = try XrayNodeSelection.model(for: node, uuid: uuid)
        #expect(model.outbound == .trojan(Trojan(address: "h", port: 1, password: uuid)))
        #expect(model.transport == .grpc(.init()))
        #expect(model.security == .tls(StreamSettings.TLS(pinnedPeerCertSha256: pin)))
        let tls = try #require((try model.proxyOutbound()["streamSettings"] as? [String: Any])?["tlsSettings"] as? [String: Any])
        #expect(tls["pinnedPeerCertSha256"] as? String == pin)
        #expect(tls["allowInsecure"] == nil)
    }

    /// The SDK decodes such inbounds as sent; they can never verify, so they are not candidates.
    @Test
    func unverifiableInboundsAreSkipped() throws {
        let keyless = XrayInbound.Reality(serverName: "", shortID: "", publicKey: "", fingerprint: "")
        let node = XrayNodeEndpoint(host: "h", inbounds: [
            XrayInbound(port: 1, proxyProtocol: .vless, transport: .tcp, security: .reality, reality: keyless),
            XrayInbound(port: 2, proxyProtocol: .vless, transport: .tcp, security: .tls, tlsPin: nil),
            XrayInbound(port: 3, proxyProtocol: .vmess, transport: .websocket, security: .none),
        ])
        let model = try XrayNodeSelection.model(for: node, uuid: uuid)
        #expect(model.outbound == .vmess(VMess(address: "h", port: 3, users: [VMess.User(id: uuid)])))

        let unverifiableOnly = XrayNodeEndpoint(host: "h", inbounds: Array(node.inbounds.prefix(2)))
        #expect(throws: XrayNodeSelection.Error.noUsableInbound) { try XrayNodeSelection.model(for: unverifiableOnly, uuid: uuid) }
    }

    @Test
    func shadowsocksOnlyNodeIsRejected() {
        let node = XrayNodeEndpoint(host: "h", inbounds: [
            XrayInbound(port: 1, proxyProtocol: .shadowsocks2022, transport: .tcp, security: .none, method: "2022-blake3-aes-256-gcm", key: "k"),
        ])
        #expect(throws: XrayNodeSelection.Error.noUsableInbound) { try XrayNodeSelection.model(for: node, uuid: uuid) }
    }

    /// REALITY values Xray-core would refuse, and quote whole in its error, are not dialled: a line break in them would
    /// reach the logs.
    @Test(arguments: [
        ("abc\n2026-11-06 forged", "0123456789abcdef", "www.apple.com"),
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9", "", ""),             // 42 characters
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9+", "", ""),            // standard base64, not base64url
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", "0123456789abcdef01", ""), // short ID past 16 digits
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", "abc", ""),          // an odd number of digits
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", "zz\n", ""),
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", "\u{FF11}\u{FF12}", ""),                 // fullwidth digits
        ("SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", "", "www.apple.com\nx"),
    ])
    func malformedRealityValuesAreNotDialled(publicKey: String, shortID: String, serverName: String) {
        let malformed = XrayInbound.Reality(serverName: serverName, shortID: shortID, publicKey: publicKey, fingerprint: "chrome")
        #expect(!XrayNodeSelection.isUsable(XrayInbound(port: 1, proxyProtocol: .vless, transport: .tcp, security: .reality, reality: malformed)))
        // An empty short ID and server name are Xray-core's to accept, as before.
        let wellFormed = XrayInbound.Reality(serverName: "", shortID: "", publicKey: reality.publicKey, fingerprint: "chrome")
        #expect(XrayNodeSelection.isUsable(XrayInbound(port: 1, proxyProtocol: .vless, transport: .tcp, security: .reality, reality: wellFormed)))
    }

    /// One SHA-256 pin, colons allowed; nothing else is dialled.
    @Test(arguments: [
        ("abababababababababababababababababababababababababababababababab", true),
        ("AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB", true),
        ("abababababababababababababababababababababababababababababababa", false),
        ("abababababababababababababababababababababababababababababababab,cdcd", false),
        ("abababababababababababababababababababababababababababababababab\n", false),
        (String(repeating: "\u{FF11}", count: 64), false),
    ])
    func aTLSInboundNeedsOneCertificatePin(pin: String, isUsable: Bool) {
        #expect(XrayNodeSelection.isUsable(XrayInbound(port: 1, proxyProtocol: .vless, transport: .tcp, security: .tls, tlsPin: pin)) == isUsable)
    }
}
