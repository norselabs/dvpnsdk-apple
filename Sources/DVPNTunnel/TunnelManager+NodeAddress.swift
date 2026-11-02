//
//  TunnelManager+NodeAddress.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK

// MARK: - Node address

extension TunnelManager {
    /// Logs the node a start connects to and stores its address for the extension's start line. Every start replaces
    /// the address, also one that then fails before its tunnel starts.
    func recordNode(of credentials: ConnectionCredentials) {
        NodeAddressStore.record(credentials.server?.address)
        logger.notice("\(Self.startLine(for: credentials), privacy: .public)")
    }

    /// "Starting the tunnel to the WIREGUARD node at 203.0.113.5 (sentnode1…)", or "(no node address)".
    nonisolated static func startLine(for credentials: ConnectionCredentials) -> String {
        let node = NodeAddressStore.describe(host: credentials.endpoint.host, address: credentials.server?.address)
        return "Starting the tunnel to the \(credentials.nodeType.rawValue) node \(node)"
    }
}

// MARK: - Private

private extension ConnectionEndpoint {
    var host: String {
        switch self {
        case let .wireGuard(endpoint): endpoint.host
        case let .amneziaWG(endpoint): endpoint.wireGuard.host
        case let .v2ray(node): node.host
        case let .xrayNode(node): node.host
        case let .hysteria(endpoint): endpoint.host
        }
    }
}
