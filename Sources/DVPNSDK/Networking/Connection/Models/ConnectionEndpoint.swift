//
//  ConnectionEndpoint.swift
//  DVPNSDK
//

import Foundation

// MARK: - ConnectionEndpoint

/// A node as its handshake metadata describes it, one case per node type. The SDK decodes what the node
/// sent (enum values this build does not know are dropped, empty strings read as `nil`); which inbound to
/// dial, TLS trust and fallbacks are the tunnel layer's decisions (`DVPNTunnel`).
public enum ConnectionEndpoint: Equatable, Sendable {
    case wireGuard(WireGuardEndpoint)
    /// `V2RAY` node: every inbound the node offers, in the earlier metadata format.
    case v2ray(V2RayNodeEndpoint)
    /// `XRAY` node: every inbound the node offers, fully described (protocol, transport, security).
    case xrayNode(XrayNodeEndpoint)
    case amneziaWG(AmneziaWGEndpoint)
    case hysteria(HysteriaEndpoint)
}

// MARK: - WireGuardEndpoint

public struct WireGuardEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let clientAddress: String
    public let peerPublicKey: String

    public init(host: String, port: UInt16, clientAddress: String, peerPublicKey: String) {
        self.host = host
        self.port = port
        self.clientAddress = clientAddress
        self.peerPublicKey = peerPublicKey
    }
}

// MARK: - V2RayNodeEndpoint

/// A `V2RAY` node as described by its handshake metadata (`sentinel-go-sdk/v2ray`, the earlier node
/// format, still deployed): the host plus one entry per inbound. Entries with values this build does
/// not know are dropped at decode time; which inbound to dial is the tunnel layer's choice
/// (`V2RayNodeSelection` in `DVPNTunnel`).
public struct V2RayNodeEndpoint: Equatable, Sendable {
    public let host: String
    public let inbounds: [V2RayInbound]

    public init(host: String, inbounds: [V2RayInbound]) {
        self.host = host
        self.inbounds = inbounds
    }
}

public struct V2RayInbound: Equatable, Sendable {
    public enum ProxyProtocol: UInt8, Sendable {
        case vless = 1
        case vmess = 2
    }

    /// The transports of the earlier enum that the Xray tunnel speaks.
    public enum Transport: UInt8, Sendable {
        case grpc = 3
        case tcp = 7
        case websocket = 8
    }

    /// Whether the inbound speaks TLS. `plaintext` is the node enum's `none`, named so that `.none` on
    /// this optional property cannot be read as `nil`.
    public enum Security: UInt8, Sendable {
        case plaintext = 1
        case tls = 2
    }

    public let port: UInt16
    public let proxyProtocol: ProxyProtocol
    public let transport: Transport
    /// `nil` when the node does not say; the tunnel layer then detects TLS at connect time.
    public let security: Security?

    public init(port: UInt16, proxyProtocol: ProxyProtocol, transport: Transport, security: Security? = nil) {
        self.port = port
        self.proxyProtocol = proxyProtocol
        self.transport = transport
        self.security = security
    }
}

// MARK: - XrayNodeEndpoint

/// An `XRAY` node as described by its handshake metadata: the host plus one entry per inbound.
/// Values mirror the Sentinel node enums (`sentinel-go-sdk/xray`); entries with values this
/// build does not know are dropped at decode time. Which inbound to dial is the tunnel layer's choice
/// (`XrayNodeSelection` in `DVPNTunnel`).
public struct XrayNodeEndpoint: Equatable, Sendable {
    public let host: String
    public let inbounds: [XrayInbound]

    public init(host: String, inbounds: [XrayInbound]) {
        self.host = host
        self.inbounds = inbounds
    }
}

public struct XrayInbound: Equatable, Sendable {
    public enum ProxyProtocol: UInt8, Sendable {
        case vless = 1
        case vmess = 2
        case trojan = 3
        case shadowsocks2022 = 4
    }

    public enum Transport: UInt8, Sendable {
        case tcp = 1
        case websocket = 2
        case grpc = 3
        case httpUpgrade = 4
        case xhttp = 5
    }

    public enum Security: UInt8, Sendable {
        case none = 1
        case tls = 2
        case reality = 3
    }

    public enum Flow: UInt8, Sendable {
        case none = 1
        case vision = 2
    }

    public struct Reality: Equatable, Sendable {
        public let serverName: String
        public let shortID: String
        public let publicKey: String
        public let fingerprint: String

        public init(serverName: String, shortID: String, publicKey: String, fingerprint: String) {
            self.serverName = serverName
            self.shortID = shortID
            self.publicKey = publicKey
            self.fingerprint = fingerprint
        }
    }

    public let port: UInt16
    public let proxyProtocol: ProxyProtocol
    public let transport: Transport
    public let security: Security
    public let flow: Flow
    /// Hex SHA-256 of the node's TLS certificate (`security == .tls`); `nil` when the node sent none.
    public let tlsPin: String?
    /// REALITY parameters as sent (`security == .reality`); a field the node left empty is `""`.
    public let reality: Reality?
    /// Shadowsocks 2022 method and server key (`proxyProtocol == .shadowsocks2022`).
    public let method: String?
    public let key: String?

    public init(
        port: UInt16,
        proxyProtocol: ProxyProtocol,
        transport: Transport,
        security: Security,
        flow: Flow = .none,
        tlsPin: String? = nil,
        reality: Reality? = nil,
        method: String? = nil,
        key: String? = nil
    ) {
        self.port = port
        self.proxyProtocol = proxyProtocol
        self.transport = transport
        self.security = security
        self.flow = flow
        self.tlsPin = tlsPin
        self.reality = reality
        self.method = method
        self.key = key
    }
}

// MARK: - AmneziaWGEndpoint

/// A WireGuard endpoint plus the AmneziaWG obfuscation parameters.
///
/// `parameters` carries the raw `[Interface]` keys exactly as they appear in an AmneziaWG
/// configuration (`Jc`, `Jmin`, `Jmax`, `S1`–`S4`, `H1`–`H4`, `I1`–`I5`, …). Validation and
/// typing happen in the tunnel layer, which owns the AmneziaWG model.
public struct AmneziaWGEndpoint: Equatable, Sendable {
    public let wireGuard: WireGuardEndpoint
    public let parameters: [String: String]

    public init(wireGuard: WireGuardEndpoint, parameters: [String: String]) {
        self.wireGuard = wireGuard
        self.parameters = parameters
    }
}

// MARK: - HysteriaEndpoint

/// A `HYSTERIA2` node as described by its handshake metadata (`sentinel-go-sdk/hysteria2`). Strings the
/// node left empty are `nil`. The tunnel layer fills `auth` from the credentials' `uid` when the node
/// sent none, and decides trust from `insecure` and `tlsPin`.
public struct HysteriaEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let auth: String?
    public let sni: String?
    public let obfsPassword: String?
    /// The node's `insecure` flag; `nil` when absent.
    public let insecure: Bool?
    /// SHA-256 fingerprint of the node's TLS certificate (hex, with or without colons).
    public let tlsPin: String?

    public init(
        host: String,
        port: UInt16,
        auth: String? = nil,
        sni: String? = nil,
        obfsPassword: String? = nil,
        insecure: Bool? = nil,
        tlsPin: String? = nil
    ) {
        self.host = host
        self.port = port
        self.auth = auth
        self.sni = sni
        self.obfsPassword = obfsPassword
        self.insecure = insecure
        self.tlsPin = tlsPin
    }
}

// MARK: - Inner DTOs

struct WireGuardHandshakeData: Decodable {
    struct Metadata: Decodable {
        let port: UInt16
        let publicKey: String
    }

    let addrs: [String]
    let metadata: [Metadata]
}

/// AmneziaWG handshake payload: the WireGuard fields plus the node's obfuscation parameters
/// (`sentinel-go-sdk/amneziawg/metadata.go`): `s1`–`s4`, `h1`–`h4` and optional `i1`–`i5` live on
/// `metadata[0]`. Junk-packet settings (`Jc`/`Jmin`/`Jmax`) are local and chosen by the client.
/// A legacy top-level `awg` dictionary is still honoured when present.
struct AmneziaWGHandshakeData: Decodable {
    struct Metadata: Decodable {
        let s1: UInt16?
        let s2: UInt16?
        let s3: UInt16?
        let s4: UInt16?
        let h1: UInt32?
        let h2: UInt32?
        let h3: UInt32?
        let h4: UInt32?
        let i1: String?
        let i2: String?
        let i3: String?
        let i4: String?
        let i5: String?
    }

    let metadata: [Metadata]
    let awg: [String: String]?

    /// The `[Interface]` keys exactly as AmneziaWG configs spell them.
    var parameters: [String: String] {
        var result = awg ?? [:]
        guard let first = metadata.first else { return result }
        let numbers: [(String, (any BinaryInteger)?)] = [
            ("S1", first.s1), ("S2", first.s2), ("S3", first.s3), ("S4", first.s4),
            ("H1", first.h1), ("H2", first.h2), ("H3", first.h3), ("H4", first.h4),
        ]
        for (key, value) in numbers {
            if let value { result[key] = String(value) }
        }
        let strings: [(String, String?)] = [("I1", first.i1), ("I2", first.i2), ("I3", first.i3), ("I4", first.i4), ("I5", first.i5)]
        for (key, value) in strings {
            if let value, !value.isEmpty { result[key] = value }
        }
        return result
    }
}

/// Port that the node may send as a number or a numeric string.
struct LenientPort: Decodable {
    let value: UInt16?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(UInt16.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = UInt16(text)
        } else {
            value = nil
        }
    }
}

struct XrayHandshakeData: Decodable {
    struct Metadata: Decodable {
        let port: LenientPort
        let proxyProtocol: UInt8
        let transportProtocol: UInt8
        let transportSecurity: UInt8?
        let flow: UInt8?
        let method: String?
        let key: String?
        let tlsPin: String?
        let realityServerName: String?
        let realityShortId: String?
        let realityPublicKey: String?
        let realityFingerprint: String?

        /// The typed `XRAY` inbound, or `nil` when a value is unknown to this build.
        var inbound: XrayInbound? {
            guard let port = port.value,
                  let proxy = XrayInbound.ProxyProtocol(rawValue: proxyProtocol),
                  let transport = XrayInbound.Transport(rawValue: transportProtocol),
                  let security = XrayInbound.Security(rawValue: transportSecurity ?? 1)
            else {
                return nil
            }
            var reality: XrayInbound.Reality?
            if security == .reality {
                reality = XrayInbound.Reality(
                    serverName: realityServerName ?? "",
                    shortID: realityShortId ?? "",
                    publicKey: realityPublicKey ?? "",
                    fingerprint: realityFingerprint ?? ""
                )
            }
            return XrayInbound(
                port: port,
                proxyProtocol: proxy,
                transport: transport,
                security: security,
                flow: flow.flatMap(XrayInbound.Flow.init(rawValue:)) ?? .none,
                tlsPin: tlsPin.nonEmpty,
                reality: reality,
                method: method.nonEmpty,
                key: key.nonEmpty
            )
        }

        /// The same entry read as `V2RAY` metadata (the earlier enums), or `nil` when a value is unknown
        /// to this build.
        var v2rayInbound: V2RayInbound? {
            guard let port = port.value,
                  let proxy = V2RayInbound.ProxyProtocol(rawValue: proxyProtocol),
                  let transport = V2RayInbound.Transport(rawValue: transportProtocol)
            else {
                return nil
            }
            return V2RayInbound(
                port: port,
                proxyProtocol: proxy,
                transport: transport,
                security: transportSecurity.flatMap(V2RayInbound.Security.init(rawValue:))
            )
        }
    }

    let metadata: [Metadata]
}

struct HysteriaHandshakeData: Decodable {
    struct Metadata: Decodable {
        let port: LenientPort
        let auth: String?
        let sni: String?
        let obfsPassword: String?
        let insecure: Bool?
        let tlsPin: String?
    }

    let metadata: [Metadata]
}

// MARK: - Empty strings

/// Go marshals an unset string as `""`; the node models read that as "not sent".
extension String? {
    var nonEmpty: String? {
        self?.isEmpty == false ? self : nil
    }
}
