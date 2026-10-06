//
//  NodeType+TunnelProtocol.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNSDK

extension NodeType {
    /// The tunnel engine that serves this node type. AmneziaWG rides on the WireGuard engine (amneziawg-go) with extra
    /// interface parameters; V2RAY and XRAY nodes both use Xray-core.
    var tunnelProtocolID: TunnelProtocolID {
        switch self {
        case .wireguard, .amneziawg: return .wireGuard
        case .v2ray, .xray: return .xray
        case .hysteria: return .hysteria
        }
    }
}
