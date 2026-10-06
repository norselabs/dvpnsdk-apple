//
//  FakeSplitTunnelProfile.swift
//  DVPNCore
//

#if os(macOS)
@testable import DVPNTunnel
import Foundation
import NetworkExtension

// MARK: - FakeSplitTunnelProfile

/// A transparent-proxy configuration whose start and stop just flip the status.
@MainActor
final class FakeSplitTunnelProfile: SplitTunnelProfile {
    var localizedDescription: String?
    var isEnabled = false
    var isOnDemandEnabled = false
    var onDemandRules: [NEOnDemandRule]?
    var protocolConfiguration: NEVPNProtocol?
    var connectionStatus: NEVPNStatus = .disconnected

    private(set) var saves = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var messages: [Data] = []
    var saveError: (any Error)?
    var startError: (any Error)?
    var messageError: (any Error)?

    init(providerBundleID: String? = nil, status: NEVPNStatus = .disconnected) {
        if let providerBundleID {
            let provider = NETunnelProviderProtocol()
            provider.providerBundleIdentifier = providerBundleID
            protocolConfiguration = provider
            isEnabled = true
        }
        connectionStatus = status
    }

    func saveToPreferences() async throws {
        saves += 1
        if let saveError { throw saveError }
    }

    func loadFromPreferences() async throws {}

    func removeFromPreferences() async throws {}

    func startProxy() throws {
        starts += 1
        if let startError { throw startError }
        connectionStatus = .connected
    }

    func stopProxy() {
        stops += 1
        connectionStatus = .disconnected
    }

    func sendMessage(_ data: Data) async throws -> Data? {
        messages.append(data)
        if let messageError { throw messageError }
        return data
    }
}

// MARK: - FakeSplitTunnelProfileStore

@MainActor
final class FakeSplitTunnelProfileStore: SplitTunnelProfileStore {
    var profiles: [FakeSplitTunnelProfile] = []
    private(set) var made: [FakeSplitTunnelProfile] = []
    var onMake: ((FakeSplitTunnelProfile) -> Void)?

    func loadAllProfiles() async throws -> [any SplitTunnelProfile] {
        profiles
    }

    func makeProfile() -> any SplitTunnelProfile {
        let profile = FakeSplitTunnelProfile()
        made.append(profile)
        onMake?(profile)
        return profile
    }
}
#endif
