//
//  TunnelProfile.swift
//  DVPNCore
//

import DVPNWireGuardCore
import Foundation
import NetworkExtension
import WireGuardKit

// MARK: - TunnelProfile

/// What the tunnel service needs from a VPN profile. In the apps it is the system's `NETunnelProviderManager`; tests
/// use a fake, so the service's activation, on-demand, status and reload logic runs without NetworkExtension.
@MainActor
protocol TunnelProfile: AnyObject {
    var localizedDescription: String? { get set }
    var isEnabled: Bool { get set }
    var isOnDemandEnabled: Bool { get set }
    var onDemandRules: [NEOnDemandRule]? { get set }
    var protocolConfiguration: NEVPNProtocol? { get set }

    /// The connection's status as the system reports it.
    var connectionStatus: NEVPNStatus { get }
    /// Whether the profile has a provider session to start, stop and message.
    var hasProviderSession: Bool { get }

    func saveToPreferences() async throws
    func loadFromPreferences() async throws
    func removeFromPreferences() async throws

    /// Asks the provider to start; does nothing without a provider session.
    func startTunnel(activationAttemptID: String) throws
    /// Asks the provider to stop; does nothing without a provider session.
    func stopTunnel()
    /// Sends a message to the running provider and returns its answer.
    func sendProviderMessage(_ message: Data) async throws -> Data?
}

// MARK: - TunnelProfileStore

/// Where the tunnel service loads and creates profiles: the system's preferences in the apps, a fake in tests.
@MainActor
protocol TunnelProfileStore {
    func loadAllProfiles() async throws -> [any TunnelProfile]
    func makeProfile() -> any TunnelProfile
}

/// The system's VPN preferences.
struct SystemTunnelProfileStore: TunnelProfileStore {
    func loadAllProfiles() async throws -> [any TunnelProfile] {
        try await NETunnelProviderManager.loadAllFromPreferences()
    }

    func makeProfile() -> any TunnelProfile {
        NETunnelProviderManager()
    }
}

// MARK: - NETunnelProviderManager

extension NETunnelProviderManager: @MainActor TunnelProfile {
    var connectionStatus: NEVPNStatus {
        connection.status
    }

    var hasProviderSession: Bool {
        providerSession != nil
    }

    func startTunnel(activationAttemptID: String) throws {
        try providerSession?.startTunnel(options: ["activationAttemptId": activationAttemptID])
    }

    func stopTunnel() {
        providerSession?.stopTunnel()
    }

    func sendProviderMessage(_ message: Data) async throws -> Data? {
        guard let session = providerSession else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private var providerSession: NETunnelProviderSession? {
        connection as? NETunnelProviderSession
    }
}

// MARK: - Helpers

extension TunnelProfile {
    var provider: NETunnelProviderProtocol? {
        protocolConfiguration as? NETunnelProviderProtocol
    }

    /// Parses the WireGuard configuration referenced by this profile (reads the config file).
    /// Callers on hot paths should avoid it; `TunnelsService.reload()` deliberately does not use it.
    var tunnelConfiguration: TunnelConfiguration? {
        guard let provider else { return nil }
        return provider.asTunnelConfiguration(with: localizedDescription)
    }

    func set(tunnelConfiguration: TunnelConfiguration) {
        protocolConfiguration = NETunnelProviderProtocol(
            tunnelConfiguration: tunnelConfiguration,
            previouslyFrom: protocolConfiguration
        )
        localizedDescription = tunnelConfiguration.name
    }

    /// Cheap identity check used by `TunnelsService.reload()`. Deliberately avoids
    /// `tunnelConfiguration`, which parses the WireGuard config file from disk.
    func isEquivalent(to tunnel: TunnelContainer) -> Bool {
        let other = tunnel.tunnelProvider
        return isSameProfile(as: other)
            && provider?.serverAddress == other.provider?.serverAddress
    }

    /// Whether `other` is this profile as another instance: the same name and the same extension. The name alone is
    /// not enough, since another app's profile can carry it.
    func isSameProfile(as other: any TunnelProfile) -> Bool {
        localizedDescription == other.localizedDescription
            && provider?.providerBundleIdentifier == other.provider?.providerBundleIdentifier
    }
}
