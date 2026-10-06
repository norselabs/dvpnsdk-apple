@testable import DVPNSDK
import Foundation
import Testing

/// Decoding of the new node types against payloads shaped exactly like the backend's (values are synthetic).
struct NodeHandshakeDecodingTests {
    private func credentials(protocol raw: String, host: String, uuid: String, data: String) throws -> ConnectionCredentials {
        let payload: [String: Any] = [
            "server_id": "srv",
            "protocol": raw,
            "connection_handshake": [
                "request": ["uuid": uuid],
                "response": ["addrs": [host], "data": data],
            ],
        ]
        return try JSONDecoder().decode(ConnectionCredentials.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    // A backend fixture, kept verbatim.
    // swiftlint:disable:next line_length
    private let xrayData = "eyJtZXRhZGF0YSI6W3sicG9ydCI6IjM4ODA4IiwicHJveHlfcHJvdG9jb2wiOjEsInRyYW5zcG9ydF9wcm90b2NvbCI6MSwidHJhbnNwb3J0X3NlY3VyaXR5IjozLCJmbG93IjoyLCJtZXRob2QiOiIiLCJrZXkiOiIiLCJ0bHNfcGluIjoiIiwicmVhbGl0eV9zZXJ2ZXJfbmFtZSI6Ind3dy5leGFtcGxlLmNvbSIsInJlYWxpdHlfc2hvcnRfaWQiOiIwMTIzNDU2Nzg5YWJjZGVmIiwicmVhbGl0eV9wdWJsaWNfa2V5IjoiU09KMUJ5elg4clFaNktKN3o1blkyRjlBNGZWcHpCMHJRZEw2d01oems5USIsInJlYWxpdHlfZmluZ2VycHJpbnQiOiJjaHJvbWUifSx7InBvcnQiOiI3MDE1IiwicHJveHlfcHJvdG9jb2wiOjEsInRyYW5zcG9ydF9wcm90b2NvbCI6NSwidHJhbnNwb3J0X3NlY3VyaXR5IjozLCJmbG93IjoxLCJtZXRob2QiOiIiLCJrZXkiOiIiLCJ0bHNfcGluIjoiIiwicmVhbGl0eV9zZXJ2ZXJfbmFtZSI6Ind3dy5leGFtcGxlLmNvbSIsInJlYWxpdHlfc2hvcnRfaWQiOiJmZWRjYmE5ODc2NTQzMjEwIiwicmVhbGl0eV9wdWJsaWNfa2V5IjoiUTd6WGs5bVliTjJwTGRGNHZHd0hzVDhyQzFlSmFVNm9LaU1uQjN4WnlWMCIsInJlYWxpdHlfZmluZ2VycHJpbnQiOiJjaHJvbWUifSx7InBvcnQiOiIzMjU3NCIsInByb3h5X3Byb3RvY29sIjoyLCJ0cmFuc3BvcnRfcHJvdG9jb2wiOjUsInRyYW5zcG9ydF9zZWN1cml0eSI6MywiZmxvdyI6MSwibWV0aG9kIjoiIiwia2V5IjoiIiwidGxzX3BpbiI6IiIsInJlYWxpdHlfc2VydmVyX25hbWUiOiJ3d3cuZXhhbXBsZS5jb20iLCJyZWFsaXR5X3Nob3J0X2lkIjoiMGYxZTJkM2M0YjVhNjk3OCIsInJlYWxpdHlfcHVibGljX2tleSI6ImRHVnpkQzF5WldGc2FYUjVMV3RsZVMxdWRXMWlaWEl0ZEdoeVpXVXRNREEiLCJyZWFsaXR5X2ZpbmdlcnByaW50IjoiY2hyb21lIn0seyJwb3J0IjoiMTM4MjQiLCJwcm94eV9wcm90b2NvbCI6MiwidHJhbnNwb3J0X3Byb3RvY29sIjo1LCJ0cmFuc3BvcnRfc2VjdXJpdHkiOjIsImZsb3ciOjEsIm1ldGhvZCI6IiIsImtleSI6IiIsInRsc19waW4iOiJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiIiwicmVhbGl0eV9zZXJ2ZXJfbmFtZSI6IiIsInJlYWxpdHlfc2hvcnRfaWQiOiIiLCJyZWFsaXR5X3B1YmxpY19rZXkiOiIiLCJyZWFsaXR5X2ZpbmdlcnByaW50IjoiIn0seyJwb3J0IjoiMjgyMTQiLCJwcm94eV9wcm90b2NvbCI6MiwidHJhbnNwb3J0X3Byb3RvY29sIjoyLCJ0cmFuc3BvcnRfc2VjdXJpdHkiOjIsImZsb3ciOjEsIm1ldGhvZCI6IiIsImtleSI6IiIsInRsc19waW4iOiJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiIiwicmVhbGl0eV9zZXJ2ZXJfbmFtZSI6IiIsInJlYWxpdHlfc2hvcnRfaWQiOiIiLCJyZWFsaXR5X3B1YmxpY19rZXkiOiIiLCJyZWFsaXR5X2ZpbmdlcnByaW50IjoiIn1dfQ=="

    @Test
    func xrayNodeDecodesEveryInbound() throws {
        let uuid = "11111111-2222-3333-4444-555555555555"
        let credentials = try credentials(protocol: "XRAY", host: "203.0.113.5", uuid: uuid, data: xrayData)
        #expect(credentials.nodeType == .xray)
        #expect(credentials.uid == uuid, "the client id comes from connection_handshake.request.uuid")

        guard case let .xrayNode(node) = credentials.endpoint else { Issue.record("expected an XRAY node"); return }
        #expect(node.host == "203.0.113.5")
        #expect(node.inbounds.count == 5)

        let vision = node.inbounds[0]
        #expect(vision.port == 38808)
        #expect(vision.proxyProtocol == .vless)
        #expect(vision.transport == .tcp)
        #expect(vision.security == .reality)
        #expect(vision.flow == .vision)
        #expect(
            vision.reality ==
                .init(serverName: "www.example.com", shortID: "0123456789abcdef", publicKey: "SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", fingerprint: "chrome")
        )
        #expect(vision.tlsPin == nil)

        #expect(node.inbounds[1].transport == .xhttp)
        #expect(node.inbounds[2].proxyProtocol == .vmess)

        let tls = node.inbounds[3]
        #expect(tls.security == .tls)
        #expect(tls.tlsPin == "abababababababababababababababababababababababababababababababab")
        #expect(tls.reality == nil)
        #expect(node.inbounds[4].transport == .websocket)
    }

    /// Unknown enum values drop the entry; everything else decodes as sent, empty strings as `nil` or `""`.
    /// Whether an inbound is usable (a TLS pin, a REALITY key) is DVPNTunnel's judgement.
    @Test
    func xrayUnknownEntriesAreDroppedAndEmptyFieldsDecodeAsAbsent() throws {
        let metadata: [[String: Any]] = [
            ["port": "1", "proxy_protocol": 9, "transport_protocol": 1, "transport_security": 1],      // unknown proxy
            ["port": "2", "proxy_protocol": 1, "transport_protocol": 1, "transport_security": 2, "tls_pin": ""],  // TLS without pin
            ["port": "3", "proxy_protocol": 1, "transport_protocol": 1, "transport_security": 3, "reality_public_key": ""],  // REALITY without key
            ["port": "4", "proxy_protocol": 4, "transport_protocol": 1, "transport_security": 1, "method": "2022-blake3-aes-256-gcm", "key": "k"],
            ["port": 5, "proxy_protocol": 1, "transport_protocol": 3],   // numeric port, security defaults to none
        ]
        let data = try JSONSerialization.data(withJSONObject: ["metadata": metadata]).base64EncodedString()
        let credentials = try credentials(protocol: "XRAY", host: "h", uuid: "u", data: data)
        guard case let .xrayNode(node) = credentials.endpoint else { Issue.record("expected an XRAY node endpoint"); return }
        #expect(node.inbounds.map(\.port) == [2, 3, 4, 5])
        #expect(node.inbounds[0].security == .tls)
        #expect(node.inbounds[0].tlsPin == nil)
        #expect(node.inbounds[1].security == .reality)
        #expect(node.inbounds[1].reality == .init(serverName: "", shortID: "", publicKey: "", fingerprint: ""))
        #expect(node.inbounds[2].proxyProtocol == .shadowsocks2022)
        #expect(node.inbounds[2].key == "k")
        #expect(node.inbounds[3].security == .none)
        #expect(node.inbounds[3].flow == .none)
    }

    @Test
    func xrayWithoutKnownInboundDecodesEmpty() throws {
        let metadata = [["port": "1", "proxy_protocol": 9, "transport_protocol": 1, "transport_security": 2]]
        let data = try JSONSerialization.data(withJSONObject: ["metadata": metadata]).base64EncodedString()
        let credentials = try credentials(protocol: "XRAY", host: "h", uuid: "u", data: data)
        #expect(credentials.endpoint == .xrayNode(XrayNodeEndpoint(host: "h", inbounds: [])))
    }

    @Test
    func hysteria2Decodes() throws {
        let uuid = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        // A backend fixture, kept verbatim.
        // swiftlint:disable:next line_length
        let data = "eyJtZXRhZGF0YSI6W3sicG9ydCI6MTc0MzUsInRsc19waW4iOiJhYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYjphYiIsIm9iZnNfcGFzc3dvcmQiOiJhYWFhYWFhYS1iYmJiLTRjY2MtOGRkZC1lZWVlZWVlZWVlZWUifV19"
        let credentials = try credentials(protocol: "HYSTERIA2", host: "203.0.113.6", uuid: uuid, data: data)
        #expect(credentials.nodeType == .hysteria)
        #expect(
            credentials.endpoint ==
                .hysteria(HysteriaEndpoint(
                    host: "203.0.113.6",
                    port: 17435,
                    auth: nil,
                    sni: nil,
                    obfsPassword: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                    insecure: nil,
                    tlsPin: "ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab"
                )),
            "the node names no auth of its own; DVPNTunnel uses the credentials' uid"
        )
    }

    @Test
    func topLevelUIDStillWins() throws {
        let responseData = try JSONSerialization.data(withJSONObject: ["metadata": [["port": 1, "tls_pin": "ab", "obfs_password": ""]]])
        let payload: [String: Any] = [
            "protocol": "HYSTERIA2", "uid": "top",
            "connection_handshake": [
                "request": ["uuid": "req"],
                "response": ["addrs": ["h"], "data": responseData.base64EncodedString()],
            ],
        ]
        let credentials = try JSONDecoder().decode(ConnectionCredentials.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(credentials.uid == "top")
        guard case let .hysteria(endpoint) = credentials.endpoint else { Issue.record("expected a Hysteria endpoint"); return }
        #expect(endpoint.auth == nil, "the fallback to the uid is DVPNTunnel's")
        #expect(endpoint.obfsPassword == nil, "an empty obfs password means the node sent none")
    }
}
