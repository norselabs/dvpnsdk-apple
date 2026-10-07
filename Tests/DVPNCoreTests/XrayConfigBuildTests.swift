//
//  XrayConfigBuildTests.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
@testable import DVPNXRayCore
import Foundation
import Testing

struct XrayConfigBuildTests {
    init() {
        DVPNCore.bootstrap(
            DVPNCoreConfiguration(
                appGroupID: "group.com.example.vpn.tests",
                protocols: [
                    TunnelProtocolDescriptor(
                        id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
                    ),
                    TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
                ]
            )
        )
    }

    @Test
    func buildConfigurationData() throws {
        let model = XConfigurationModel(
            outbound: .vmess(VMess(address: "192.0.2.10", port: 443, users: [VMess.User(id: "test-uid")])),
            transport: .ws(.init()),
            security: .tls(StreamSettings.TLS(serverName: "192.0.2.10"))
        )

        let data = try model.buildConfigurationData(localProxy: .fixture)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let inbounds = try #require(json["inbounds"] as? [[String: Any]])
        #expect(inbounds.count == 1)
        #expect(inbounds[0]["port"] as? Int == 8080)
        #expect(inbounds[0]["protocol"] as? String == "socks")

        let outbounds = try #require(json["outbounds"] as? [[String: Any]])
        #expect(outbounds.map { $0["tag"] as? String } == ["proxy", "direct", "block"])
        #expect(outbounds[0]["protocol"] as? String == "vmess")

        let streamSettings = try #require(outbounds[0]["streamSettings"] as? [String: Any])
        #expect(streamSettings["network"] as? String == "ws")
        #expect(streamSettings["security"] as? String == "tls")
        #expect(streamSettings["wsSettings"] != nil)
        let tlsSettings = try #require(streamSettings["tlsSettings"] as? [String: Any])
        #expect(tlsSettings["serverName"] as? String == "192.0.2.10")
        #expect(tlsSettings["allowInsecure"] == nil, "removed in Xray-core 26.x; must never be emitted")
        #expect(tlsSettings["pinnedPeerCertSha256"] == nil)

        #expect(json["routing"] != nil)
    }

    /// A sniffed name only chooses a route: the node connects to the address the device looked up through its chosen
    /// DNS, instead of looking the name up again with its own resolver.
    @Test
    func sniffedNamesOnlyChooseARoute() throws {
        let data = try XrayDocumentBuilder.build(proxyOutbound: ["protocol": "freedom"], localProxy: .fixture)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbounds = try #require(json["inbounds"] as? [[String: Any]])
        let sniffing = try #require(inbounds.first?["sniffing"] as? [String: Any])

        #expect(sniffing["enabled"] as? Bool == true)
        #expect(sniffing["routeOnly"] as? Bool == true)
    }

    /// The complete document for a production-shaped XRAY node (VLESS + REALITY + Vision over RAW wins
    /// over four others), pinned as a fixture: a change to the selection or the builders shows up as a
    /// diff. Record a new fixture with `DVPN_RECORD_FIXTURES=1 scripts/test.sh --filter xrayNodeDocument`.
    @Test
    func xrayNodeDocumentMatchesTheFixture() throws {
        let uuid = "11111111-2222-3333-4444-555555555555"
        let pin = "abababababababababababababababababababababababababababababababab"
        let reality = XrayInbound.Reality(
            serverName: "www.example.com", shortID: "0123456789abcdef", publicKey: "SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", fingerprint: "chrome"
        )
        let node = XrayNodeEndpoint(host: "203.0.113.5", inbounds: [
            XrayInbound(port: 28214, proxyProtocol: .vmess, transport: .websocket, security: .tls, tlsPin: pin),
            XrayInbound(port: 13824, proxyProtocol: .vmess, transport: .xhttp, security: .tls, tlsPin: pin),
            XrayInbound(port: 32574, proxyProtocol: .vmess, transport: .xhttp, security: .reality, reality: reality),
            XrayInbound(port: 7015, proxyProtocol: .vless, transport: .xhttp, security: .reality, reality: reality),
            XrayInbound(port: 38808, proxyProtocol: .vless, transport: .tcp, security: .reality, flow: .vision, reality: reality),
        ])
        var model = try XrayNodeSelection.model(for: node, uuid: uuid)
        model.obfuscation = .tlsFragment(.init())
        let localProxy = LocalProxy(port: 10808, username: "user", password: "pass")
        let rendered = try canonicalJSON(try model.buildConfigurationData(localProxy: localProxy, assetDirectory: "/var/assets"))

        if ProcessInfo.processInfo.environment["DVPN_RECORD_FIXTURES"] != nil {
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/xray-node-document.json")
            try rendered.write(to: fixture, atomically: true, encoding: .utf8)
            return
        }
        let expected = try canonicalJSON(Data(contentsOf: TestFixtures.url("xray-node-document", extension: "json")))
        #expect(rendered == expected)
    }

    private func canonicalJSON(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self) + "\n"
    }
}
