//
//  SplitTunnelSettings.swift
//  DVPNCore
//

import Foundation

// MARK: - SplitTunnelSettings

/// Which apps bypass the VPN on macOS. The app writes it; the split-tunnel extension reads it
/// when it starts and decides flow by flow.
public struct SplitTunnelSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Every app uses the VPN; the extension is not started.
        case disabled
        /// Only the selected apps use the VPN; every other app bypasses it.
        case allowSelected
        /// Every app uses the VPN except the selected ones.
        case exceptSelected
    }

    public var mode: Mode
    /// The selected apps, by signing identifier (an app's bundle ID).
    public var apps: Set<String>

    public init(mode: Mode = .disabled, apps: Set<String> = []) {
        self.mode = mode
        self.apps = apps
    }

    public static let disabled = SplitTunnelSettings()

    /// Whether the extension has anything to do.
    public var isEnabled: Bool { mode != .disabled }

    /// Whether a flow from the app signed as `signingIdentifier` leaves the VPN. A system process reports an empty
    /// identifier, which counts as "not selected".
    public func bypassesVPN(_ signingIdentifier: String) -> Bool {
        switch mode {
        case .disabled:
            return false
        case .exceptSelected:
            return isSelected(signingIdentifier)
        case .allowSelected:
            return !isSelected(signingIdentifier)
        }
    }

    /// A selected app, or one of its helpers: a process whose identifier extends a selected app's with a dot (an app's
    /// network often runs in a helper, such as `com.example.app.helper`).
    func isSelected(_ signingIdentifier: String) -> Bool {
        guard !signingIdentifier.isEmpty else { return false }
        return apps.contains(signingIdentifier) || apps.contains { signingIdentifier.hasPrefix($0 + ".") }
    }
}
