//
//  TunnelManager+NodeAddress.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK

// MARK: - Node address

extension TunnelManager {
    /// Refuses a node whose address the decoder would have refused: credentials built by hand never met its checks.
    /// Runs before the start line, which logs the address.
    func checkAddress(of credentials: ConnectionCredentials) throws(TunnelsServiceError) {
        let host = credentials.endpoint.host
        guard ConnectionCredentials.isNodeHost(host), !ConnectionCredentials.isNonPublicAddress(host) else {
            let node = NodeAddressStore.describe(host: host.escapingControlCharacters, address: credentials.server?.address)
            logger.error("Refused the \(credentials.nodeType.rawValue, privacy: .public) node \(node, privacy: .public): not a public address")
            throw .refusedNodeAddress
        }
    }

    /// Refuses a node given as a host name that resolves to an address that is not public (`NodeAddress.check`). The
    /// node's packet tunnel provider runs the same check on every start the system makes.
    func checkResolvedAddress(of credentials: ConnectionCredentials) async throws(TunnelsServiceError) {
        let host = credentials.endpoint.host
        guard case let .refused(address) = await NodeAddress.check(host) else { return }
        let node = NodeAddressStore.describe(host: host.escapingControlCharacters, address: credentials.server?.address)
        logger.error(
            "Refused the \(credentials.nodeType.rawValue, privacy: .public) node \(node, privacy: .public): it resolves to \(address, privacy: .public), not a public address"
        )
        throw .refusedNodeAddress
    }

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

// MARK: - Host

extension ConnectionEndpoint {
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
