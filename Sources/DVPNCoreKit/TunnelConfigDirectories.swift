//
//  TunnelConfigDirectories.swift
//  DVPNCore
//

import Foundation

@frozen
public enum TunnelConfigDirectories {
    public static var suiteName: String { TunnelEnvironment.appGroupID }

    private static func createDirectory(at url: URL?) throws -> URL {
        guard let url else {
            throw NSError.newError("Config file does not exist")
        }
        guard FileManager.default.fileExists(atPath: url.path) == false else {
            return url
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    /// Root of the tunnel configuration files inside the App Group container.
    ///
    /// tvOS only lets apps write to `Library/Caches` (and `tmp`) inside their containers and treats the
    /// data as purgeable; creating `Library/Application Support` there fails. The app rewrites every
    /// config file right before it activates a tunnel, so a purge costs nothing but one reconnect.
    public static let homeDirectory: URL? = {
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
                "Unable to create the tunnel config directory: \(error.localizedDescription, privacy: .public)"
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

    /// The resolvers for a proxy tunnel. Builds up to 2.4.0 stored a comma-separated string, which a
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
