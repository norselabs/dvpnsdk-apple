//
//  SplitTunnelSettingsStore.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

// MARK: - SplitTunnelSettingsStore

/// The settings' home: one JSON value in the App Group defaults, so the extension reads what the app last saved.
public enum SplitTunnelSettingsStore {
    static let key = "SPLIT_TUNNEL"

    public static func save(_ settings: SplitTunnelSettings) throws {
        try save(settings, in: .shared)
    }

    /// The saved settings; disabled when nothing was saved or it does not decode.
    public static func load() -> SplitTunnelSettings {
        load(from: .shared)
    }

    package static func save(_ settings: SplitTunnelSettings, in defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }

    package static func load(from defaults: UserDefaults) -> SplitTunnelSettings {
        guard let data = defaults.data(forKey: key) else { return .disabled }
        do {
            return try JSONDecoder().decode(SplitTunnelSettings.self, from: data)
        } catch {
            logger.error("Split-tunnel settings do not decode: \(error.localizedDescription, privacy: .public)")
            return .disabled
        }
    }
}
