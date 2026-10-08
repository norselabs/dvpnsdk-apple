//
//  XraySourceStore.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

// MARK: - TunnelConfigDirectories: xray

public extension TunnelConfigDirectories {
    static let xrayCurrentConfigKey = "XRAY_CURRENT"
}

// MARK: - XraySourceError

public enum XraySourceError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case noStoredConfiguration
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Xray config directory does not exist"
        case .noStoredConfiguration:
            return "No stored Xray configuration"
        case let .unreadable(reason):
            return "Stored Xray configuration is unreadable (written by an older app version?): \(reason). Reconnect from the app."
        }
    }
}

// MARK: - XraySourceStore

/// Stores the current `XraySource` in the App Group so the extension can read it on start.
public enum XraySourceStore {
    static var configURL: URL? {
        TunnelConfigDirectories.configDirectory?
            .appending(component: TunnelConfigDirectories.xrayCurrentConfigKey, directoryHint: .isDirectory)
            .appending(component: "config.json")
    }

    public static func save(_ source: XraySource) throws {
        guard let destinationURL = configURL else {
            throw XraySourceError.storageUnavailable
        }
        let folderURL = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(source)
        // Atomic and throwing: a failed write must fail the start, not leave the previous node's config to run.
        try data.write(to: destinationURL, options: .atomic)
        logger.info("Xray source saved")
    }

    public static func loadCurrent() throws(XraySourceError) -> XraySource {
        guard let configURL, FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            throw .noStoredConfiguration
        }
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(XraySource.self, from: data)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    public static func delete() throws {
        guard let folderURL = configURL?.deletingLastPathComponent() else { return }
        if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: folderURL)
        }
    }

    public static func exists() -> Bool {
        guard let configURL else { return false }
        return FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false))
    }

    /// Deletes a stored file that no longer decodes (the pre-`XraySource` flat model format).
    /// The app rewrites the file on the next connect. Idempotent; returns `true` when a file was removed.
    @discardableResult
    public static func removeIfUnreadable() -> Bool {
        guard exists() else { return false }
        do {
            _ = try loadCurrent()
            return false
        } catch {
            logger.info("Removing unreadable Xray configuration: \(error.localizedDescription, privacy: .public)")
            try? delete()
            return true
        }
    }
}
