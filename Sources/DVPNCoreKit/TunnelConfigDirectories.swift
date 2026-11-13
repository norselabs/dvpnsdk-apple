//
//  TunnelConfigDirectories.swift
//  DVPNSDK
//

import Foundation

@frozen
public enum TunnelConfigDirectories {
    public static var suiteName: String { TunnelEnvironment.appGroupID }

    private static func createDirectory(at url: URL?) throws -> URL {
        guard var url else {
            throw NSError.newError("Config file does not exist")
        }
        if FileManager.default.fileExists(atPath: url.path) == false {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        excludeFromBackup(&url)
        return url
    }

    /// Marks `url` as excluded from device backups, unless it already is. The flag belongs to the directory, not to
    /// the files in it, so a directory an earlier version made gets it here, and a file written atomically keeps it.
    private static func excludeFromBackup(_ url: inout URL) {
        do {
            guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true else {
                return
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            logger.error("Unable to exclude the tunnel config directory from backups: \(error.logDescription, privacy: .public)")
        }
    }

    /// How every engine writes its configuration file: atomically, readable from the device's first unlock on.
    package static let configurationFileWriting: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication,
    ]

    /// Root of the tunnel configuration files: inside the App Group container, or the directory a test task keeps them in.
    package static var homeDirectory: URL? {
        guard let homeDirectoryOverride else { return appGroupHomeDirectory }
        return try? createDirectory(at: homeDirectoryOverride)
    }

    /// Where the configuration files go for the task that sets it, instead of the App Group container, which a test
    /// process cannot write. Only that task and its child tasks see it, so the tests running beside it keep theirs.
    @TaskLocal package static var homeDirectoryOverride: URL?

    /// tvOS only lets apps write to `Library/Caches` (and `tmp`) inside their containers and treats the
    /// data as purgeable; creating `Library/Application Support` there fails. The app rewrites every
    /// config file right before it activates a tunnel, so a purge costs nothing but one reconnect.
    private static let appGroupHomeDirectory: URL? = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TunnelEnvironment.appGroupID) else {
            logger.error("No App Group container for \(TunnelEnvironment.appGroupID, privacy: .public)")
            return nil
        }
#if os(tvOS)
        let url = containerURL.appendingPathComponent("Library/Caches/Xray")
#else
        let url = containerURL.appendingPathComponent("Library/Application Support/Xray")
#endif
        do {
            return try TunnelConfigDirectories.createDirectory(at: url)
        } catch {
            logger.error(
                "Unable to create the tunnel config directory: \(error.logDescription, privacy: .public)"
            )
            return nil
        }
    }()

    public static var assetDirectory: URL? {
        try? TunnelConfigDirectories.createDirectory(
            at: TunnelConfigDirectories.homeDirectory?.appending(component: "assets", directoryHint: .isDirectory)
        )
    }

    public static var configDirectory: URL? {
        try? TunnelConfigDirectories.createDirectory(
            at: TunnelConfigDirectories.homeDirectory?.appending(component: "configs", directoryHint: .isDirectory)
        )
    }
}

package extension TunnelConfigDirectories {
    static let dnsKey = "DNS"

    /// Hands the app's DNS choice to the proxy extensions, which read it back with `dns(in:)`.
    static func storeDNS(_ dns: DNSServerType, in defaults: UserDefaults = .shared) {
        defaults.set(dns.addresses, forKey: dnsKey)
    }

    /// The resolvers for a proxy tunnel. Older builds stored a comma-separated string, which a
    /// system on-demand start can still find before the app connects again; with nothing stored, the
    /// default provider applies.
    static func dns(in defaults: UserDefaults = .shared) -> [String] {
        if let servers = defaults.stringArray(forKey: dnsKey), !servers.isEmpty {
            return servers
        }
        let servers = defaults.string(forKey: dnsKey).splitToArray(trimmingCharacters: .whitespaces)
        return servers.isEmpty ? DNSServerType.default.addresses : servers
    }
}

public extension TunnelConfigDirectories {
    static var wireguardConfigDirectory: URL? {
        try? TunnelConfigDirectories.createDirectory(
            at: TunnelConfigDirectories.homeDirectory?.appending(component: "wireguard", directoryHint: .isDirectory)
        )
    }

    static let wireguardCurrentConfigKey = "WIREGUARD_CURRENT"
}

public extension TunnelConfigDirectories {
    static var cachesDirectory: URL {
        URL(filePath: NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0])
    }
}
