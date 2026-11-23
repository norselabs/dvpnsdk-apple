//
//  XrayNodeEndpoint+Model.swift
//  DVPNSDK
//

import DVPNSDK
import DVPNXRayCore
import Foundation

// MARK: - XrayNodeSelection

/// Picks the inbound of an `XRAY` node this client should dial and renders it as a typed model.
///
/// Preference order: REALITY over TLS over plaintext; VLESS over VMess over Trojan (Shadowsocks 2022
/// is not modelled); RAW over XHTTP over gRPC over WebSocket over HTTPUpgrade. The node's own
/// client template renders the same fields (REALITY: fingerprint/publicKey/serverName/shortId;
/// TLS: fingerprint + `pinnedPeerCertSha256`), so nothing has to be probed. The SDK hands over every
/// inbound as the node sent it; what can be dialled is decided here.
enum XrayNodeSelection {
    enum Error: Swift.Error, Equatable {
        case noUsableInbound
    }

    /// Shadowsocks 2022 is not modelled; a TLS inbound without a pin or a REALITY inbound without a
    /// public key could never verify, so neither is dialled. Nor is one whose pin or REALITY values Xray-core
    /// would refuse.
    static func isUsable(_ inbound: XrayInbound) -> Bool {
        guard inbound.proxyProtocol != .shadowsocks2022 else { return false }
        switch inbound.security {
        case .none: return true
        case .tls: return inbound.tlsPin.map(isCertificatePin) == true
        case .reality: return inbound.reality.map(isUsable) == true
        }
    }

    /// A SHA-256 digest in hex, colons allowed between the bytes: one pin, as `pinnedPeerCertSha256` reads it.
    static func isCertificatePin(_ pin: String) -> Bool {
        let digits = pin.replacingOccurrences(of: ":", with: "")
        return digits.count == 64 && digits.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// The values Xray-core's REALITY client accepts: a 32-byte public key in unpadded base64url, a short ID of up to
    /// 16 hex digits in pairs, and a server name that is empty or a host name.
    static func isUsable(_ reality: XrayInbound.Reality) -> Bool {
        let key = reality.publicKey
        let isBase64URL = key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let keyBytes = Data(base64Encoded: key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "=")
        let shortID = reality.shortID
        return key.count == 43 && isBase64URL && keyBytes?.count == 32
            && shortID.count <= 16 && shortID.count.isMultiple(of: 2) && shortID.allSatisfy { $0.isASCII && $0.isHexDigit }
            && (reality.serverName.isEmpty || ConnectionCredentials.isNodeHost(reality.serverName))
    }

    static func model(for node: XrayNodeEndpoint, uuid: String) throws(Error) -> XConfigurationModel {
        let candidates = node.inbounds.filter(isUsable)
        guard let inbound = candidates.max(by: { score($0) < score($1) }) else {
            throw .noUsableInbound
        }

        let outbound: XOutbound
        switch inbound.proxyProtocol {
        case .vless:
            outbound = .vless(VLESS(
                address: node.host,
                port: Int(inbound.port),
                users: [VLESS.User(id: uuid, flow: inbound.flow == .vision ? .xtlsRprxVision : nil)]
            ))
        case .vmess:
            outbound = .vmess(VMess(address: node.host, port: Int(inbound.port), users: [VMess.User(id: uuid)]))
        case .trojan:
            // The node derives the Trojan password from the client UUID.
            outbound = .trojan(Trojan(address: node.host, port: Int(inbound.port), password: uuid))
        case .shadowsocks2022:
            throw .noUsableInbound
        }

        let transport: XTransport = switch inbound.transport {
        case .tcp: .tcp(.init())
        case .websocket: .ws(.init())
        case .grpc: .grpc(.init())
        case .httpUpgrade: .httpupgrade(.init())
        case .xhttp: .xhttp(.init())
        }

        let security: XSecurity
        switch inbound.security {
        case .none:
            security = .none
        case .tls:
            security = .tls(StreamSettings.TLS(pinnedPeerCertSha256: inbound.tlsPin))
        case .reality:
            let reality = inbound.reality
            security = .reality(StreamSettings.Reality(
                fingerprint: Fingerprint(rawValue: reality?.fingerprint ?? "") ?? .chrome,
                serverName: reality?.serverName ?? "",
                publicKey: reality?.publicKey ?? "",
                shortId: reality?.shortID ?? ""
            ))
        }

        return XConfigurationModel(outbound: outbound, transport: transport, security: security)
    }

    static func score(_ inbound: XrayInbound) -> Int {
        let security = switch inbound.security {
        case .reality: 200
        case .tls: 100
        case .none: 0
        }
        let proxy = switch inbound.proxyProtocol {
        case .vless: 30
        case .vmess: 20
        case .trojan: 10
        case .shadowsocks2022: 0
        }
        let transport = switch inbound.transport {
        case .tcp: 5
        case .xhttp: 4
        case .grpc: 3
        case .websocket: 2
        case .httpUpgrade: 1
        }
        return security + proxy + transport
    }
}
