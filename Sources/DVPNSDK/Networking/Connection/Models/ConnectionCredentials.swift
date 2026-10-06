//
//  ConnectionCredentials.swift
//  DVPNSDK
//

import Foundation

// MARK: - Credentials

public struct ConnectionCredentials: Equatable, Sendable {
    public let nodeType: NodeType

    public let serverID: String?
    public let server: Server?

    public let endpoint: ConnectionEndpoint
    public let privateKey: String?
    public let uid: String?

    public init(
        nodeType: NodeType,
        endpoint: ConnectionEndpoint,
        uid: String? = nil,
        privateKey: String? = nil,
        server: Server? = nil,
        serverID: String? = nil
    ) {
        self.nodeType = nodeType
        self.server = server
        self.serverID = serverID ?? server?.id
        self.endpoint = endpoint
        self.uid = uid
        self.privateKey = privateKey
    }
}

// MARK: - Decodable

extension ConnectionCredentials: Decodable {
    enum CodingKeys: String, CodingKey {
        case nodeType = "protocol"
        case privateKey = "private_key"
        case uid
        case serverID = "server_id"
        case server
        case connectionHandshake = "connection_handshake"
    }

    enum HandshakeKeys: String, CodingKey {
        case request
        case response
    }

    enum HandshakeRequestKeys: String, CodingKey {
        case uuid
    }

    enum HandshakeResponseKeys: String, CodingKey {
        case addrs
        case data
    }

    // One pass over the envelope, then one branch per node type; the node is decoded as sent.
    // swiftlint:disable:next function_body_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawType = try container.decode(String.self, forKey: .nodeType)
        guard let nodeType = NodeType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(
                forKey: .nodeType,
                in: container,
                debugDescription: "Unknown node type '\(rawType)'"
            )
        }
        self.nodeType = nodeType

        server = try? container.decode(Server.self, forKey: .server)
        serverID = try? container.decode(String.self, forKey: .serverID)
        privateKey = try? container.decode(String.self, forKey: .privateKey)

        let handshake = try container.nestedContainer(
            keyedBy: HandshakeKeys.self,
            forKey: .connectionHandshake
        )
        // New node types identify the client by the UUID echoed in the handshake request.
        let requestUUID = (try? handshake.nestedContainer(keyedBy: HandshakeRequestKeys.self, forKey: .request))
            .flatMap { try? $0.decode(String.self, forKey: .uuid) }
        uid = (try? container.decode(String.self, forKey: .uid)) ?? requestUUID
        let response = try handshake.nestedContainer(
            keyedBy: HandshakeResponseKeys.self,
            forKey: .response
        )

        let addrs = try response.decode([String].self, forKey: .addrs)
        guard let host = addrs.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .addrs,
                in: response,
                debugDescription: "connection_handshake.response.addrs is empty"
            )
        }

        let dataString = try response.decode(String.self, forKey: .data)
        guard let dataBytes = Data(base64Encoded: dataString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .data,
                in: response,
                debugDescription: "connection_handshake.response.data is not valid base64"
            )
        }

        let innerDecoder = JSONDecoder.snakeCase

        switch nodeType {
        case .wireguard:
            endpoint = .wireGuard(
                try Self.wireGuardEndpoint(host: host, data: dataBytes, decoder: innerDecoder, in: response)
            )

        case .amneziawg:
            let wireGuard = try Self.wireGuardEndpoint(host: host, data: dataBytes, decoder: innerDecoder, in: response)
            let extras = try innerDecoder.decode(AmneziaWGHandshakeData.self, from: dataBytes)
            endpoint = .amneziaWG(AmneziaWGEndpoint(wireGuard: wireGuard, parameters: extras.parameters))

        case .v2ray:
            let inner = try innerDecoder.decode(XrayHandshakeData.self, from: dataBytes)
            endpoint = .v2ray(V2RayNodeEndpoint(host: host, inbounds: inner.metadata.compactMap(\.v2rayInbound)))

        case .xray:
            let inner = try innerDecoder.decode(XrayHandshakeData.self, from: dataBytes)
            endpoint = .xrayNode(XrayNodeEndpoint(host: host, inbounds: inner.metadata.compactMap(\.inbound)))

        case .hysteria:
            let inner = try innerDecoder.decode(HysteriaHandshakeData.self, from: dataBytes)
            guard let metadata = inner.metadata.first else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data,
                    in: response,
                    debugDescription: "Hysteria handshake metadata is empty"
                )
            }
            guard let port = metadata.port.value else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data,
                    in: response,
                    debugDescription: "Hysteria metadata port is not a valid UInt16"
                )
            }
            endpoint = .hysteria(
                HysteriaEndpoint(
                    host: host,
                    port: port,
                    auth: metadata.auth.nonEmpty,
                    sni: metadata.sni.nonEmpty,
                    obfsPassword: metadata.obfsPassword.nonEmpty,
                    insecure: metadata.insecure,
                    tlsPin: metadata.tlsPin.nonEmpty
                )
            )
        }
    }

    private static func wireGuardEndpoint(
        host: String,
        data: Data,
        decoder: JSONDecoder,
        in response: KeyedDecodingContainer<HandshakeResponseKeys>
    ) throws -> WireGuardEndpoint {
        let inner = try decoder.decode(WireGuardHandshakeData.self, from: data)
        guard let firstAddr = inner.addrs.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .data,
                in: response,
                debugDescription: "WireGuard handshake addrs is empty"
            )
        }
        guard let firstMetadata = inner.metadata.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .data,
                in: response,
                debugDescription: "WireGuard handshake metadata is empty"
            )
        }
        let clientAddress = firstAddr.split(separator: "/").first.map(String.init) ?? firstAddr
        return WireGuardEndpoint(
            host: host,
            port: firstMetadata.port,
            clientAddress: clientAddress,
            peerPublicKey: firstMetadata.publicKey
        )
    }
}
