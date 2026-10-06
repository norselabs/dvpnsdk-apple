//
//  ProxyStartErrorStore.swift
//  DVPNCore
//

import Foundation

// MARK: - ProxyStartError

package struct ProxyStartError: Codable, Sendable, Equatable {
    package let message: String
    package let date: Date
}

// MARK: - ProxyStartErrorStore

/// NetworkExtension does not forward a provider's thrown error text to the app. The proxy extensions (Xray,
/// Hysteria) record why they failed to start here (App Group defaults), so the app's log names the reason,
/// e.g. libXray's "no valid outbound found" or libhysteria's, next to the activation failure.
package enum ProxyStartErrorStore {
    package static let key = "PROXY_LAST_START_ERROR"

    package static func record(_ message: String, in defaults: UserDefaults = .shared) {
        let error = ProxyStartError(message: message, date: Date())
        if let data = try? JSONEncoder().encode(error) {
            defaults.set(data, forKey: key)
        }
    }

    package static func load(from defaults: UserDefaults = .shared) -> ProxyStartError? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ProxyStartError.self, from: data)
    }

    package static func clear(in defaults: UserDefaults = .shared) {
        defaults.removeObject(forKey: key)
    }
}
