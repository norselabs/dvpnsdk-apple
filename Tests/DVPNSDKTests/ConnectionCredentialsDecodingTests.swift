@testable import DVPNSDK
import Foundation
import Testing

/// The WireGuard key the handshake request carries, and the top-level copy the backend is removing.
private let keyInRequest = "oK56DE9Ue9zHAt61A8xBeLjd9zLOUlGmk8hYB7sTf1k="
private let keyAtTopLevel = "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U="

struct ConnectionCredentialsDecodingTests {
    /// A credentials answer's `data`. `request` is the handshake request's fields; nil leaves the request out.
    private func credentialsJSON(
        protocol rawProtocol: String,
        handshake: [String: Any],
        addrs: [String] = ["203.0.113.10"],
        topLevelKey: String? = keyAtTopLevel,
        request: [String: Any]? = nil
    ) throws -> Data {
        let inner = try JSONSerialization.data(withJSONObject: handshake)
        var connectionHandshake: [String: Any] = [
            "response": [
                "addrs": addrs,
                "data": inner.base64EncodedString(),
            ],
        ]
        connectionHandshake["request"] = request
        var payload: [String: Any] = [
            "protocol": rawProtocol,
            "uid": "test-uid",
            "server_id": "srv-1",
            "connection_handshake": connectionHandshake,
        ]
        payload["private_key"] = topLevelKey
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func decodedKey(protocol rawProtocol: String = "WIREGUARD", topLevelKey: String?, request: [String: Any]?) throws -> String? {
        let data = try credentialsJSON(protocol: rawProtocol, handshake: wireGuardHandshake, topLevelKey: topLevelKey, request: request)
        return try JSONDecoder().decode(ConnectionCredentials.self, from: data).privateKey
    }

    // MARK: - The WireGuard key

    /// The key is read from the handshake request, for AmneziaWG as for WireGuard.
    @Test(arguments: ["WIREGUARD", "AMNEZIAWG"])
    func theKeyComesFromTheHandshakeRequest(protocol rawProtocol: String) throws {
        let key = try decodedKey(
            protocol: rawProtocol,
            topLevelKey: nil,
            request: ["uuid": "test-uid", "private_key": keyInRequest]
        )
        #expect(key == keyInRequest)
    }

    @Test
    func theRequestsKeyWinsOverTheTopLevelCopy() throws {
        let key = try decodedKey(topLevelKey: keyAtTopLevel, request: ["uuid": "test-uid", "private_key": keyInRequest])
        #expect(key == keyInRequest)
    }

    /// An answer from a backend that still sends only the top-level copy, or a blank key in the request.
    @Test(arguments: [nil, ["uuid": "test-uid"], ["uuid": "test-uid", "private_key": ""]] as [[String: String]?])
    func theTopLevelCopyIsReadWhenTheRequestHasNoKey(request: [String: String]?) throws {
        #expect(try decodedKey(topLevelKey: keyAtTopLevel, request: request) == keyAtTopLevel)
    }

    /// An answer with no key still decodes; starting a WireGuard tunnel from it fails (`TunnelManagerActivationTests`).
    @Test
    func noKeyDecodesAsNone() throws {
        #expect(try decodedKey(topLevelKey: nil, request: ["uuid": "test-uid"]) == nil)
    }

    // MARK: - Node types

    private let wireGuardHandshake: [String: Any] = [
        "addrs": ["10.10.0.2/32"],
        "metadata": [["port": 51820, "public_key": "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="]],
    ]

    @Test
    func wireGuardDecodesUnchanged() throws {
        let data = try credentialsJSON(protocol: "WIREGUARD", handshake: wireGuardHandshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)

        #expect(credentials.nodeType == .wireguard)
        #expect(credentials.serverID == "srv-1")
        #expect(
            credentials.endpoint ==
                .wireGuard(WireGuardEndpoint(
                    host: "203.0.113.10",
                    port: 51820,
                    clientAddress: "10.10.0.2",
                    peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
                ))
        )
    }

    /// V2RAY nodes keep the earlier enums (VLESS 1 / VMess 2; gRPC 3, TCP 7, WebSocket 8; security none 1 / tls 2).
    /// Every inbound this build knows is decoded as sent; which one to dial is DVPNTunnel's decision.
    @Test
    func v2RayDecodesEveryKnownInbound() throws {
        let handshake: [String: Any] = [
            "metadata": [
                ["port": "443", "proxy_protocol": 1, "transport_protocol": 7, "transport_security": 1],
                ["port": "8443", "proxy_protocol": 2, "transport_protocol": 3],
                ["port": "444", "proxy_protocol": 1, "transport_protocol": 5],   // mKCP: not spoken by the Xray tunnel
                ["port": "445", "proxy_protocol": 9, "transport_protocol": 8],   // unknown proxy protocol
                ["port": "8444", "proxy_protocol": 1, "transport_protocol": 8, "transport_security": 2],
            ],
        ]
        let data = try credentialsJSON(protocol: "V2RAY", handshake: handshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)

        #expect(credentials.nodeType == .v2ray)
        #expect(
            credentials.endpoint ==
                .v2ray(V2RayNodeEndpoint(host: "203.0.113.10", inbounds: [
                    V2RayInbound(port: 443, proxyProtocol: .vless, transport: .tcp, security: .plaintext),
                    V2RayInbound(port: 8443, proxyProtocol: .vmess, transport: .grpc, security: nil),
                    V2RayInbound(port: 8444, proxyProtocol: .vless, transport: .websocket, security: .tls),
                ]))
        )
    }

    @Test
    func v2RayWithoutKnownInboundsDecodesEmpty() throws {
        let handshake: [String: Any] = ["metadata": [["port": "443", "proxy_protocol": 1, "transport_protocol": 5]]]
        let data = try credentialsJSON(protocol: "V2RAY", handshake: handshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)
        #expect(credentials.endpoint == .v2ray(V2RayNodeEndpoint(host: "203.0.113.10", inbounds: [])))
    }

    /// The wire values, in the order a request names several node types; "all" is not one.
    @Test
    func nodeTypesAndTheirWireValues() {
        #expect(NodeType.allCases.map(\.rawValue) == ["WIREGUARD", "V2RAY", "XRAY", "AMNEZIAWG", "HYSTERIA2"])
        #expect(NodeType.allCases.wireValue == "WIREGUARD,V2RAY,XRAY,AMNEZIAWG,HYSTERIA2")
        #expect(NodeType(rawValue: "") == nil)
        #expect(NodeType(rawValue: "HYSTERIA") == nil)
    }

    /// A server keeps the node type as sent; it reads as a node type whatever its case, or as none it does not know.
    @Test
    func aServersNodeType() {
        func server(_ value: String) -> Server {
            Server(id: "s", countryID: "de", cityID: "ber", name: "s", isAvailable: true, serverProtocol: value)
        }
        #expect(server("XRAY").nodeType == .xray)
        #expect(server("hysteria2").nodeType == .hysteria)
        #expect(server("SHADOWSOCKS").nodeType == nil)
    }

    @Test
    func credentialsNeverDecodeAsAll() throws {
        let data = try credentialsJSON(protocol: "", handshake: wireGuardHandshake)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ConnectionCredentials.self, from: data) }
    }

    @Test
    func unknownProtocolThrows() throws {
        let data = try credentialsJSON(protocol: "OPENVPN", handshake: wireGuardHandshake)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ConnectionCredentials.self, from: data) }
    }

    /// The node format (sentinel-go-sdk/amneziawg/metadata.go): obfuscation fields on metadata[0].
    @Test
    func amneziaWGDecodesNodeMetadata() throws {
        let handshake: [String: Any] = [
            "addrs": ["10.10.0.2/32"],
            "metadata": [[
                "port": 22893, "public_key": "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=",
                "s1": 15, "s2": 18, "s3": 0, "s4": 7,
                "h1": 1234567891, "h2": 1234567892, "h3": 1234567893, "h4": 1234567894,
                "i1": "<b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>",
            ]],
        ]
        let data = try credentialsJSON(protocol: "AMNEZIAWG", handshake: handshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)

        #expect(credentials.nodeType == .amneziawg)
        guard case let .amneziaWG(endpoint) = credentials.endpoint else {
            Issue.record("Expected AmneziaWG endpoint"); return
        }
        #expect(endpoint.wireGuard.port == 22893)
        #expect(endpoint.wireGuard.clientAddress == "10.10.0.2")
        #expect(
            endpoint.parameters ==
                [
                    "S1": "15", "S2": "18", "S3": "0", "S4": "7",
                    "H1": "1234567891", "H2": "1234567892", "H3": "1234567893", "H4": "1234567894",
                    "I1": "<b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>",
                ]
        )
        #expect(endpoint.parameters["Jc"] == nil, "junk-packet settings are chosen by the client, not the node")
    }

    @Test
    func amneziaWGLegacyDictionaryStillDecodes() throws {
        var handshake = wireGuardHandshake
        handshake["awg"] = ["Jc": "4", "Jmin": "40", "Jmax": "70", "S1": "15", "S2": "18", "H1": "123456"]
        let data = try credentialsJSON(protocol: "AMNEZIAWG", handshake: handshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)

        guard case let .amneziaWG(endpoint) = credentials.endpoint else {
            Issue.record("Expected AmneziaWG endpoint"); return
        }
        #expect(endpoint.parameters["Jc"] == "4")
        #expect(endpoint.parameters["H1"] == "123456")
    }

    @Test
    func amneziaWGWithoutExtrasDecodesEmptyParameters() throws {
        let data = try credentialsJSON(protocol: "AMNEZIAWG", handshake: wireGuardHandshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)

        guard case let .amneziaWG(endpoint) = credentials.endpoint else {
            Issue.record("Expected AmneziaWG endpoint"); return
        }
        #expect(endpoint.parameters.isEmpty)
    }

    /// The Hysteria fields decode as sent; trust (`insecure`, the pin) and the `auth` fallback are DVPNTunnel's.
    @Test
    func hysteriaDecodes() throws {
        let handshake: [String: Any] = [
            "metadata": [["port": "8443", "auth": "secret", "sni": "example.com", "obfs_password": "salamander-pw", "insecure": true]],
        ]
        let data = try credentialsJSON(protocol: "HYSTERIA2", handshake: handshake)
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: data)

        #expect(credentials.nodeType == .hysteria)
        #expect(
            credentials.endpoint ==
                .hysteria(HysteriaEndpoint(
                    host: "203.0.113.10",
                    port: 8443,
                    auth: "secret",
                    sni: "example.com",
                    obfsPassword: "salamander-pw",
                    insecure: true
                ))
        )
    }
}
