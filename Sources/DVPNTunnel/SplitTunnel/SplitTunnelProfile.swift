//
//  SplitTunnelProfile.swift
//  DVPNCore
//

#if os(macOS)
import Foundation
import NetworkExtension

// MARK: - SplitTunnelProfile

/// What the split-tunnel manager needs from a transparent-proxy configuration: the system's
/// `NETransparentProxyManager` in the app, a fake in tests.
@MainActor
protocol SplitTunnelProfile: AnyObject {
    var localizedDescription: String? { get set }
    var isEnabled: Bool { get set }
    var isOnDemandEnabled: Bool { get set }
    var onDemandRules: [NEOnDemandRule]? { get set }
    var protocolConfiguration: NEVPNProtocol? { get set }

    /// The proxy's status as the system reports it.
    var connectionStatus: NEVPNStatus { get }

    func saveToPreferences() async throws
    func loadFromPreferences() async throws
    func removeFromPreferences() async throws

    func startProxy() throws
    func stopProxy()
    /// Hands `data` to the running proxy (`handleAppMessage`) and returns its answer.
    func sendMessage(_ data: Data) async throws -> Data?
}

extension SplitTunnelProfile {
    var providerBundleID: String? {
        (protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
    }
}

// MARK: - SplitTunnelProfileStore

/// Where the manager loads and creates proxy configurations: the system's preferences in the app, a fake in tests.
@MainActor
protocol SplitTunnelProfileStore {
    func loadAllProfiles() async throws -> [any SplitTunnelProfile]
    func makeProfile() -> any SplitTunnelProfile
}

struct SystemSplitTunnelProfileStore: SplitTunnelProfileStore {
    func loadAllProfiles() async throws -> [any SplitTunnelProfile] {
        try await NETransparentProxyManager.loadAllFromPreferences()
    }

    func makeProfile() -> any SplitTunnelProfile {
        NETransparentProxyManager()
    }
}

// MARK: - NETransparentProxyManager

extension NETransparentProxyManager: @MainActor SplitTunnelProfile {
    var connectionStatus: NEVPNStatus {
        connection.status
    }

    func startProxy() throws {
        try connection.startVPNTunnel()
    }

    func stopProxy() {
        connection.stopVPNTunnel()
    }

    func sendMessage(_ data: Data) async throws -> Data? {
        guard let session = connection as? NETunnelProviderSession else { throw NEVPNError(.configurationInvalid) }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
