//
//  FakeTunnelProfile.swift
//  DVPNCore
//

import DVPNCoreKit
@testable import DVPNTunnel
import Foundation
import NetworkExtension

// MARK: - FakeTunnelProfile

/// A VPN profile whose provider does what the test scripts, and reports each status change the way NetworkExtension's
/// notification does (`onStatusChange`).
@MainActor
final class FakeTunnelProfile: TunnelProfile {
    /// What one start attempt does.
    enum StartOutcome {
        /// The provider reaches `.connected`.
        case connect
        /// The provider stays `.connecting`.
        case stayConnecting
        /// The provider stops again (`.disconnected`).
        case fail
        /// `startTunnel` itself throws.
        case throwing(any Error)
    }

    var localizedDescription: String?
    var isEnabled = true
    var isOnDemandEnabled = false
    var onDemandRules: [NEOnDemandRule]?
    var protocolConfiguration: NEVPNProtocol?
    var connectionStatus: NEVPNStatus = .disconnected
    var hasProviderSession = true

    /// One outcome per attempt; the last one repeats.
    var startOutcomes: [StartOutcome] = [.connect]
    var saveError: (any Error)?
    /// The provider's answer to a message: for WireGuard, its runtime configuration.
    var messageAnswer: Data?
    /// Runs when a start attempt begins, before its outcome (the extension recording why it failed, for instance).
    var onStart: (() -> Void)?
    var onStatusChange: ((FakeTunnelProfile) -> Void)?

    private(set) var saves = 0
    private(set) var loads = 0
    private(set) var removals = 0
    private(set) var starts = 0
    private(set) var stops = 0

    init(name: String? = nil, providerBundleID: String? = nil, status: NEVPNStatus = .disconnected) {
        localizedDescription = name
        connectionStatus = status
        if let providerBundleID {
            let provider = NETunnelProviderProtocol()
            provider.providerBundleIdentifier = providerBundleID
            provider.serverAddress = name
            protocolConfiguration = provider
        }
    }

    func saveToPreferences() async throws {
        saves += 1
        if let saveError { throw saveError }
    }

    func loadFromPreferences() async throws {
        loads += 1
    }

    func removeFromPreferences() async throws {
        removals += 1
    }

    func startTunnel(activationAttemptID: String) throws {
        starts += 1
        onStart?()
        let outcome = startOutcomes.count > 1 ? startOutcomes.removeFirst() : startOutcomes.first ?? .connect
        switch outcome {
        case .connect:
            report(.connecting)
            report(.connected)
        case .stayConnecting:
            report(.connecting)
        case .fail:
            report(.connecting)
            report(.disconnected)
        case let .throwing(error):
            throw error
        }
    }

    func stopTunnel() {
        stops += 1
        report(.disconnected)
    }

    func sendProviderMessage(_ message: Data) async throws -> Data? {
        messageAnswer
    }

    func report(_ status: NEVPNStatus) {
        connectionStatus = status
        onStatusChange?(self)
    }
}

// MARK: - FakeTunnelProfileStore

@MainActor
final class FakeTunnelProfileStore: TunnelProfileStore {
    var profiles: [FakeTunnelProfile] = []
    private(set) var made: [FakeTunnelProfile] = []
    var onMake: ((FakeTunnelProfile) -> Void)?

    func loadAllProfiles() async throws -> [any TunnelProfile] {
        profiles
    }

    func makeProfile() -> any TunnelProfile {
        let profile = FakeTunnelProfile()
        made.append(profile)
        onMake?(profile)
        return profile
    }
}

// MARK: - FakeTunnelSettings

final class FakeTunnelSettings: TunnelSettingsProviding {
    let selectedDNS: DNSServerType = .cloudflare
}
