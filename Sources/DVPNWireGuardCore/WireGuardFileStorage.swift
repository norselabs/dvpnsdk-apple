//
//  WireGuardFileStorage.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation
import WireGuardKit

// MARK: - WireGuardFileConfiguration

/// The WireGuard (or AmneziaWG: same format, extra `[Interface]` keys) tunnel stored in the App Group.
public struct WireGuardFileConfiguration: Codable, Sendable {
    let name: String
    let wireGuardConfig: String
    let createdAt: Date
    let modifiedAt: Date

    init(name: String, tunnelConfiguration: TunnelConfiguration) {
        self.name = name
        wireGuardConfig = tunnelConfiguration.asWgQuickConfig()
        createdAt = Date()
        modifiedAt = Date()
    }

    func toTunnelConfiguration() throws -> TunnelConfiguration {
        try TunnelConfiguration(fromWgQuickConfig: wireGuardConfig, called: name)
    }
}

// MARK: - WireGuardFileStorage

final class WireGuardFileStorage {
    static func save(
        tunnelConfiguration: TunnelConfiguration,
        named name: String
    ) throws {
        guard let folderURL = TunnelConfigDirectories.wireguardConfigDirectory?.appending(
            component: TunnelConfigDirectories.wireguardCurrentConfigKey,
            directoryHint: .isDirectory
        ) else {
            throw NSError.newError("WireGuard config directory does not exist")
        }

        if !FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
        }

        let config = WireGuardFileConfiguration(name: name, tunnelConfiguration: tunnelConfiguration)
        let destinationURL = folderURL.appending(component: "config.json")
        let data = try JSONEncoder().encode(config)

        // Atomic and throwing: a failed write must fail the start, not leave the previous node's config to run.
        try data.write(to: destinationURL, options: .atomic)

        logger.info("WireGuard config saved to file: \(destinationURL.path(percentEncoded: false), privacy: .public)")
    }

    static func load() throws -> TunnelConfiguration? {
        guard let folderURL = TunnelConfigDirectories.wireguardConfigDirectory?.appending(
            component: TunnelConfigDirectories.wireguardCurrentConfigKey,
            directoryHint: .isDirectory
        ) else {
            return nil
        }

        let configURL = folderURL.appending(component: "config.json")

        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            logger.info("WireGuard config file does not exist at: \(configURL.path(percentEncoded: false), privacy: .public)")
            return nil
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(WireGuardFileConfiguration.self, from: data)

        logger.info("WireGuard config loaded from file: \(configURL.path(percentEncoded: false), privacy: .public)")
        return try config.toTunnelConfiguration()
    }

    static func delete() throws {
        guard let folderURL = TunnelConfigDirectories.wireguardConfigDirectory?.appending(
            component: TunnelConfigDirectories.wireguardCurrentConfigKey,
            directoryHint: .isDirectory
        ) else {
            return
        }

        if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: folderURL)
            logger.info("WireGuard config deleted from: \(folderURL.path(percentEncoded: false), privacy: .public)")
        }
    }

    static func exists() -> Bool {
        guard let folderURL = TunnelConfigDirectories.wireguardConfigDirectory?.appending(
            component: TunnelConfigDirectories.wireguardCurrentConfigKey,
            directoryHint: .isDirectory
        ) else {
            return false
        }

        let configURL = folderURL.appending(component: "config.json")
        return FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false))
    }
}
