//
//  TunnelStateStore.swift
//  DVPNCore
//

import Foundation
import notify

// MARK: - TunnelStateStore

/// Whether DVPN's packet tunnel is up, as its provider last said: the packet tunnels write it when they start and
/// stop, whoever started them (the app, System Settings, on-demand), and the macOS split-tunnel proxy, which the
/// system keeps running, acts only while it is. App Group defaults, plus a notification after
/// every change so the proxy need not poll.
package enum TunnelStateStore {
    package static let key = "TUNNEL_IS_UP"

    /// The notify(3) name posted after every change.
    package static var changeNotification: String {
        "\(TunnelEnvironment.appGroupID).tunnel-state"
    }

    /// The node the tunnel connects to: an address or a host name, or nil when it is down or did not say.
    package static let serverKey = "TUNNEL_SERVER"

    /// `server` is the node the tunnel connects to, kept while it is up so the split-tunnel proxy is never offered
    /// the tunnel's own traffic to it.
    package static func record(
        isUp: Bool,
        server: String? = nil,
        in defaults: UserDefaults = .shared,
        notifying: Bool = true
    ) {
        defaults.set(isUp, forKey: key)
        if isUp, let server, !server.isEmpty {
            defaults.set(server, forKey: serverKey)
        } else {
            defaults.removeObject(forKey: serverKey)
        }
        if notifying { notify_post(changeNotification) }
    }

    package static func server(in defaults: UserDefaults = .shared) -> String? {
        defaults.string(forKey: serverKey)
    }

    package static func isUp(in defaults: UserDefaults = .shared) -> Bool {
        defaults.bool(forKey: key)
    }
}
