//
//  TunnelManager+NodeAddress.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK

// MARK: - Node address

extension TunnelManager {
    /// Logs the node a start connects to, before anything can fail.
    func logStart(of credentials: ConnectionCredentials) {
        logger.notice("\(Self.startLine(for: credentials), privacy: .public)")
    }

    /// Stores the node's address for the extension's start line once the start is past its checks, just before it saves
    /// its configuration: a start that fails earlier leaves the address of the configuration a restart runs.
    func recordAddress(of credentials: ConnectionCredentials) {
        NodeAddressStore.record(credentials.server?.address)
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
