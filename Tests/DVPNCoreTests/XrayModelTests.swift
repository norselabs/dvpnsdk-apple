//
//  XrayModelTests.swift
//  DVPNCore
//

import DVPNCoreKit
@testable import DVPNXRayCore
import Foundation
import Testing

struct XrayModelTests {
    init() {
        DVPNCore.bootstrap(
            DVPNCoreConfiguration(
                appGroupID: "group.com.example.vpn.tests",
                protocols: [
                    TunnelProtocolDescriptor(id: .wireGuard, providerBundleID: "wg", tunnelName: "WireGuard", readiness: .wireGuardHandshake),
                    TunnelProtocolDescriptor(id: .xray, providerBundleID: "xray", tunnelName: "Xray", readiness: .immediate),
                ]
            )
        )
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Sum-type Codable shape

    @Test
    func transportAndSecurityEncodeWithDiscriminators() throws {
        let model = XConfigurationModel(
            outbound: .vless(VLESS(address: "example.com", port: 443, users: [VLESS.User(id: "uid", flow: .xtlsRprxVision)])),
            transport: .ws(StreamSettings.WebSocket(path: "/ws", headers: ["Host": "example.com"])),
            security: .tls(StreamSettings.TLS(serverName: "example.com"))
        )
        let object = try json(JSONEncoder().encode(model))

        let transport = try #require(object["transport"] as? [String: Any])
        #expect(transport["network"] as? String == "ws")
        #expect((transport["settings"] as? [String: Any])?["path"] as? String == "/ws")
        let security = try #require(object["security"] as? [String: Any])
        #expect(security["security"] as? String == "tls")
        #expect((security["settings"] as? [String: Any])?["serverName"] as? String == "example.com")
        let outbound = try #require(object["outbound"] as? [String: Any])
        #expect(outbound["protocol"] as? String == "vless")

        #expect(try JSONDecoder().decode(XConfigurationModel.self, from: JSONEncoder().encode(model)) == model)
    }

    @Test
    func securityNoneHasNoSettingsAndDecodesWithoutThem() throws {
        let object = try json(JSONEncoder().encode(XSecurity.none))
        #expect(object["security"] as? String == "none")
        #expect(object["settings"] == nil)
        #expect(try JSONDecoder().decode(XSecurity.self, from: Data("{\"security\":\"reality\"}".utf8)) == .reality(.init()))
        #expect(try JSONDecoder().decode(XTransport.self, from: Data("{\"network\":\"xhttp\"}".utf8)) == .xhttp(.init()))
    }

    @Test
    func transportRoundTripsForEveryNetwork() throws {
        for network in XNetwork.allCases {
            let transport = XTransport(network: network)
            #expect(transport.network == network)
            #expect(try JSONDecoder().decode(XTransport.self, from: JSONEncoder().encode(transport)) == transport)
        }
    }

    // MARK: Proxy outbound rendering

    @Test
    func vMessWebSocketTLSOutbound() throws {
        let model = XConfigurationModel(
            outbound: .vmess(VMess(address: "192.0.2.10", port: 443, users: [VMess.User(id: "uid")])),
            transport: .ws(StreamSettings.WebSocket(path: "/ws", headers: ["Host": "example.com"])),
            security: .tls(StreamSettings.TLS(serverName: "example.com", pinnedPeerCertSha256: "ab" + String(repeating: "cd", count: 31)))
        )
        let proxy = try model.proxyOutbound()

        #expect(proxy["protocol"] as? String == "vmess")
        let vnext = try #require(((proxy["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])?.first)
        #expect(vnext["address"] as? String == "192.0.2.10")
        #expect(((vnext["users"] as? [[String: Any]])?.first)?["security"] as? String == "auto")
        let stream = try #require(proxy["streamSettings"] as? [String: Any])
        #expect(stream["network"] as? String == "ws")
        #expect(stream["security"] as? String == "tls")
        #expect((stream["wsSettings"] as? [String: Any])?["path"] as? String == "/ws")
        #expect(((stream["tlsSettings"] as? [String: Any])?["pinnedPeerCertSha256"] as? String)?.count == 64)
        #expect((stream["tlsSettings"] as? [String: Any])?["allowInsecure"] == nil)
        #expect(stream["realitySettings"] == nil)
    }

    @Test
    func vlessRealityVisionAndTrojanOutbounds() throws {
        let vless = XConfigurationModel(
            outbound: .vless(VLESS(address: "203.0.113.5", port: 443, users: [VLESS.User(id: "uid", flow: .xtlsRprxVision)])),
            transport: .tcp(.init()),
            security: .reality(StreamSettings.Reality(serverName: "www.microsoft.com", publicKey: "pbk", shortId: "0123"))
        )
        let proxy = try vless.proxyOutbound()
        let user = try #require((((proxy["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])?.first?["users"] as? [[String: Any]])?.first)
        #expect(user["flow"] as? String == "xtls-rprx-vision")
        #expect(user["encryption"] as? String == "none")
        let stream = try #require(proxy["streamSettings"] as? [String: Any])
        #expect(stream["security"] as? String == "reality")
        #expect((stream["realitySettings"] as? [String: Any])?["shortId"] as? String == "0123")

        let trojan = try XConfigurationModel(
            outbound: .trojan(Trojan(address: "h", port: 443, password: "secret")),
            transport: .grpc(.init(serviceName: "svc"))
        ).proxyOutbound()
        #expect(trojan["protocol"] as? String == "trojan")
        #expect((((trojan["settings"] as? [String: Any])?["servers"] as? [[String: Any]])?.first)?["password"] as? String == "secret")
        #expect(((trojan["streamSettings"] as? [String: Any])?["grpcSettings"] as? [String: Any])?["serviceName"] as? String == "svc")
    }

    @Test
    func flowIsOmittedWhenNil() throws {
        let proxy = try XConfigurationModel(outbound: .vless(VLESS(address: "h", port: 1, users: [VLESS.User(id: "uid")]))).proxyOutbound()
        let user = try #require((((proxy["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])?.first?["users"] as? [[String: Any]])?.first)
        #expect(!user.keys.contains("flow"))
    }

    // MARK: Autodetect

    @Test
    func autodetectRoundTripsAndIsNeverRendered() throws {
        let model = XConfigurationModel(
            outbound: .vmess(VMess(address: "192.0.2.10", port: 443, users: [VMess.User(id: "uid")])),
            transport: .ws(.init()),
            security: .autodetect(StreamSettings.TLS(serverName: "192.0.2.10"))
        )
        let data = try JSONEncoder().encode(XraySource.model(model))
        #expect(try JSONDecoder().decode(XraySource.self, from: data) == .model(model))
        let security = try json(JSONEncoder().encode(model.security))
        #expect(security["security"] as? String == "autodetect")
        #expect((security["settings"] as? [String: Any])?["serverName"] as? String == "192.0.2.10")
        #expect(try JSONDecoder().decode(XSecurity.self, from: Data("{\"security\":\"autodetect\"}".utf8)) == .autodetect(.init()))

        #expect(throws: XConfigurationError.unresolvedSecurity) { try model.proxyOutbound() }
        #expect(throws: (any Error).self) { try model.buildConfigurationData(localProxy: .fixture) }
    }

    @Test
    func resolvedAutodetectRendersPinnedTLS() throws {
        var pinned = StreamSettings.TLS(serverName: "192.0.2.10")
        pinned.pinnedPeerCertSha256 = TestFixtures.selfSignedPin
        let model = XConfigurationModel(
            outbound: .vmess(VMess(address: "192.0.2.10", port: 443, users: [VMess.User(id: "uid")])),
            transport: .tcp(.init()),
            security: .tls(pinned)
        )
        let stream = try #require(try model.proxyOutbound()["streamSettings"] as? [String: Any])
        #expect(stream["security"] as? String == "tls")
        let tls = try #require(stream["tlsSettings"] as? [String: Any])
        #expect(tls["pinnedPeerCertSha256"] as? String == TestFixtures.selfSignedPin)
        #expect(tls["serverName"] as? String == "192.0.2.10")
        #expect(tls["allowInsecure"] == nil)
    }

    // MARK: Obfuscation

    @Test
    func obfuscationDefaultsToNoneAndDecodesWhenAbsent() throws {
        let model = XConfigurationModel(outbound: .vmess(VMess(address: "h", port: 1)), transport: .tcp(.init()))
        #expect(model.obfuscation == .none)
        let object = try json(JSONEncoder().encode(model))
        #expect((object["obfuscation"] as? [String: Any])?["mode"] as? String == "none")
        #expect((object["obfuscation"] as? [String: Any])?["settings"] == nil)

        // A file written before the key existed.
        var legacy = object
        legacy.removeValue(forKey: "obfuscation")
        let decoded = try JSONDecoder().decode(XConfigurationModel.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded == model)

        let stream = try #require(try model.proxyOutbound()["streamSettings"] as? [String: Any])
        #expect(stream["sockopt"] == nil)
        #expect(try model.supportingOutbounds().count == 0)
    }

    @Test
    func tlsFragmentRoundTripsAndRendersDialerProxy() throws {
        let model = XConfigurationModel(
            outbound: .vless(VLESS(address: "example.com", port: 443, users: [VLESS.User(id: "uid")])),
            transport: .tcp(.init()),
            security: .tls(StreamSettings.TLS(serverName: "example.com")),
            obfuscation: .tlsFragment(.init())
        )
        let data = try JSONEncoder().encode(XraySource.model(model))
        #expect(try JSONDecoder().decode(XraySource.self, from: data) == .model(model))
        #expect(
            try JSONDecoder().decode(XObfuscation.self, from: Data("{\"mode\":\"tlsFragment\"}".utf8)) ==
                .tlsFragment(.init())
        )

        let stream = try #require(try model.proxyOutbound()["streamSettings"] as? [String: Any])
        #expect((stream["sockopt"] as? [String: Any])?["dialerProxy"] as? String == "fragment")

        let supporting = try model.supportingOutbounds()
        #expect(supporting.count == 1)
        #expect(supporting[0]["tag"] as? String == "fragment")
        #expect(supporting[0]["protocol"] as? String == "freedom")
        let fragment = try #require((supporting[0]["settings"] as? [String: Any])?["fragment"] as? [String: Any])
        #expect(fragment["packets"] as? String == "tlshello")
        #expect(fragment["length"] as? String == "100-200")
        #expect(fragment["interval"] as? String == "10-20")

        let document = try json(try model.buildConfigurationData(localProxy: .fixture))
        let outbounds = try #require(document["outbounds"] as? [[String: Any]])
        #expect(outbounds.map { $0["tag"] as? String } == ["proxy", "fragment", "direct", "block"])
    }

    // MARK: Document

    @Test
    func documentWrapsAnyOutboundAndForcesProxyTag() throws {
        let document = try XrayDocumentBuilder.document(proxyOutbound: ["protocol": "freedom", "tag": "whatever"], localProxy: .fixture)
        let inbounds = try #require(document["inbounds"] as? [[String: Any]])
        #expect(inbounds.count == 1)
        #expect(inbounds[0]["listen"] as? String == "[::1]")
        #expect(inbounds[0]["port"] as? Int == 8080)
        #expect(inbounds[0]["protocol"] as? String == "socks")
        // Only hev-socks5-tunnel, which gets the same credentials, may use the inbound.
        let settings = try #require(inbounds[0]["settings"] as? [String: Any])
        #expect(settings["auth"] as? String == "password")
        #expect(settings["accounts"] as? [[String: String]] == [["user": "user", "pass": "pass"]])
        let outbounds = try #require(document["outbounds"] as? [[String: Any]])
        #expect(outbounds.map { $0["tag"] as? String } == ["proxy", "direct", "block"])
        #expect(document["routing"] != nil)
        #expect(document["env"] == nil)

        let withAssets = try XrayDocumentBuilder.document(proxyOutbound: ["protocol": "freedom"], localProxy: .fixture, assetDirectory: "/tmp/assets")
        #expect(withAssets["env"] as? [String: String] == ["xray.location.asset": "/tmp/assets"])
    }

    // MARK: XraySource

    @Test
    func xraySourceRoundTrips() throws {
        let model = XConfigurationModel(outbound: .vmess(VMess(address: "h", port: 1)), transport: .tcp(.init()))
        let source = XraySource.model(model)
        let data = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(XraySource.self, from: data) == source)
        #expect(try json(data)["kind"] as? String == "model")
        let shareText = Data("{\"kind\":\"shareText\",\"text\":\"vless://x\"}".utf8)
        #expect(throws: (any Error).self, "share text is no longer a source") { try JSONDecoder().decode(XraySource.self, from: shareText) }
    }

    @Test
    func oldFlatModelJSONIsNotAValidSource() {
        let legacy = Data("""
        {"vmess":{"address":"192.0.2.10","port":443,"users":[{"id":"uid","alterId":0,"security":"auto"}]},"network":"ws",
         "security":"tls","tls":{"serverName":"","allowInsecure":true,"alpn":["h2","http/1.1"],"fingerprint":"chrome"}}
        """.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(XraySource.self, from: legacy) }
    }
}
