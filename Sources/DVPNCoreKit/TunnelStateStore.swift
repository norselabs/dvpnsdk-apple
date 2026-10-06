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

    package static func record(isUp: Bool, in defaults: UserDefaults = .shared, notifying: Bool = true) {
        defaults.set(isUp, forKey: key)
        if notifying { notify_post(changeNotification) }
    }

    package static func isUp(in defaults: UserDefaults = .shared) -> Bool {
        defaults.bool(forKey: key)
    }
}
