//
//  NETunnelProviderProtocol+Extension.swift
//  DVPNCore
//

import DVPNCoreKit
import NetworkExtension
import WireGuardKit

public enum PacketTunnelProviderError: String, Error, Sendable {
    case savedProtocolConfigurationIsInvalid
    case dnsResolutionFailure
    case couldNotStartBackend
    case couldNotDetermineFileDescriptor
    case couldNotSetNetworkSettings
    case adapterInvalidState
}

public extension NETunnelProviderProtocol {
    convenience init?(
        tunnelConfiguration: TunnelConfiguration,
        previouslyFrom old: NEVPNProtocol? = nil
    ) {
        self.init()
        guard let name = tunnelConfiguration.name else { return nil }
        providerBundleIdentifier = TunnelEnvironment.requiredConfiguration.requiredDescriptor(for: .wireGuard).providerBundleID

        // Use file-based storage (no keychain)
        do {
            try WireGuardFileStorage.save(
                tunnelConfiguration: tunnelConfiguration,
                named: name
            )

            // Signal that we're using file-based storage
            providerConfiguration = [
                "WireGuardStorageType": "file",
                "WireGuardConfigName": name,
            ]

            // Set serverAddress for display purposes
            let endpoints = tunnelConfiguration.peers.compactMap(\.endpoint)
            if endpoints.isEmpty {
                serverAddress = "Unspecified"
            } else if endpoints.count == 1 {
                serverAddress = endpoints[0].stringRepresentation
            } else {
                serverAddress = "Multiple endpoints"
            }

        } catch {
            logger.error("Failed to save WireGuard config to file: \(error, privacy: .public)")
            return nil
        }
    }

    func asTunnelConfiguration(with name: String? = nil) -> TunnelConfiguration? {
        // Load from file-based storage
        do {
            return try WireGuardFileStorage.load()
        } catch {
            logger.error("Failed to load WireGuard config from file: \(error, privacy: .public)")
            return nil
        }
    }

    func destroyConfigurationReference() {
        // Clean up file-based storage
        try? WireGuardFileStorage.delete()
    }

    func verifyConfigurationReference() -> Bool {
        // Verify file-based storage
        return WireGuardFileStorage.exists()
    }

    @discardableResult
    func migrateConfigurationIfNeeded(with name: String) -> Bool {
        // No migration needed for file-based storage
        return false
    }
}
