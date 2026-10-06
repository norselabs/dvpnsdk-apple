//
//  V2RayNodeEndpoint+Model.swift
//  DVPNCore
//

import DVPNSDK
import DVPNXRayCore

// MARK: - V2RayNodeSelection

/// Picks the inbound of a `V2RAY` node this client should dial and renders it as a typed model.
///
/// V2RAY nodes are the earlier Xray-core node type and remain deployed. Their metadata names the
/// proxy protocol and the transport but says nothing reliable about TLS, so the model carries
/// `XSecurity.autodetect` and the extension handshakes with the node first. VMess is
/// preferred when both are offered: it works with or without TLS, whereas Xray-core refuses plaintext
/// VLESS towards a public address and TLS is only detected at start. A VLESS inbound the node marks
/// plaintext can therefore never connect and is skipped. These nodes predate Vision: VLESS runs without flow.
enum V2RayNodeSelection {
    enum Error: Swift.Error, Equatable {
        /// No inbound over a transport this client speaks.
        case noUsableInbound
        /// Only VLESS without TLS, which Xray-core refuses towards a public address.
        case plaintextVLESSOnly
    }

    static func model(for node: V2RayNodeEndpoint, uuid: String) throws(Error) -> XConfigurationModel {
        guard !node.inbounds.isEmpty else { throw .noUsableInbound }
        let usable = node.inbounds.filter { !($0.proxyProtocol == .vless && $0.security == .plaintext) }
        guard let inbound = usable.first(where: { $0.proxyProtocol == .vmess }) ?? usable.first else {
            throw .plaintextVLESSOnly
        }

        let outbound: XOutbound = switch inbound.proxyProtocol {
        case .vmess: .vmess(VMess(address: node.host, port: Int(inbound.port), users: [VMess.User(id: uuid)]))
        case .vless: .vless(VLESS(address: node.host, port: Int(inbound.port), users: [VLESS.User(id: uuid)]))
        }
        let transport: XTransport = switch inbound.transport {
        case .tcp: .tcp(.init())
        case .grpc: .grpc(.init())
        case .websocket: .ws(.init())
        }
        return XConfigurationModel(
            outbound: outbound,
            transport: transport,
            security: .autodetect(StreamSettings.TLS(serverName: node.host))
        )
    }
}
