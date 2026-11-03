//
//  NodeAddressStore.swift
//  DVPNSDK
//

import Foundation

// MARK: - NodeAddressStore

/// The network address (`sentnode…`) of the node whose configuration the last start saved, for the packet tunnels' start
/// lines: `TunnelManager.start(from:)` writes it, or its absence, once a start is past its checks, so a restart or an
/// on-demand start, which get no new credentials, name the node they start again, unless saving that configuration
/// failed. App Group defaults.
package enum NodeAddressStore {
    package static let key = "TUNNEL_NODE_ADDRESS"

    /// Keeps `address`; without one, forgets the previous, so a start without one does not name the previous node.
    package static func record(_ address: String?, in defaults: UserDefaults = .shared) {
        if let address, !address.isEmpty {
            defaults.set(address, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    package static func load(from defaults: UserDefaults = .shared) -> String? {
        defaults.string(forKey: key)
    }

    /// A packet tunnel's start line: "Starting the tunnel to the node at 203.0.113.5 (sentnode1…)", with the address
    /// stored for it, or "(no node address)".
    package static func startLine(host: String?, in defaults: UserDefaults = .shared) -> String {
        "Starting the tunnel to the node \(describe(host: host, address: load(from: defaults)))"
    }

    /// How a start line names the node: "at 203.0.113.5 (sentnode1…)", or "(no node address)" without one.
    package static func describe(host: String?, address: String?) -> String {
        let address = address.flatMap { $0.isEmpty ? nil : $0 }
        return "at \(host ?? "an unknown host") (\(address ?? "no node address"))"
    }
}
