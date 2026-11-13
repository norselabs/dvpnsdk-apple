//
//  HysteriaConfigurationStore.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation

// MARK: - TunnelConfigDirectories: hysteria

public extension TunnelConfigDirectories {
    static var hysteriaConfigDirectory: URL? {
        guard let url = homeDirectory?.appending(component: "hysteria", directoryHint: .isDirectory) else {
            return nil
        }
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static let hysteriaCurrentConfigKey = "HYSTERIA_CURRENT"
}

// MARK: - HysteriaConfigurationStore

/// Stores the current Hysteria configuration in the App Group so the extension can read it on start.
package enum HysteriaConfigurationStore {
    private static var configURL: URL? {
        TunnelConfigDirectories.hysteriaConfigDirectory?
            .appending(component: TunnelConfigDirectories.hysteriaCurrentConfigKey, directoryHint: .isDirectory)
            .appending(component: "config.json")
    }

    package static func save(_ configuration: HysteriaConfiguration) throws {
        guard let destinationURL = configURL else {
            throw HysteriaError.storageUnavailable
        }
        let folderURL = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(configuration)
        // Atomic and throwing: a failed write must fail the start, not leave the previous node's config to run.
        try data.write(to: destinationURL, options: TunnelConfigDirectories.configurationFileWriting)
        logger.info("Hysteria config saved")
    }

    package static func loadCurrent() throws -> HysteriaConfiguration {
        guard let configURL, FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            throw HysteriaError.noStoredConfiguration
        }
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(HysteriaConfiguration.self, from: data)
    }

    package static func delete() throws {
        guard let folderURL = configURL?.deletingLastPathComponent() else { return }
        if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: folderURL)
        }
    }

    package static func exists() -> Bool {
        guard let configURL else { return false }
        return FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false))
    }
}
