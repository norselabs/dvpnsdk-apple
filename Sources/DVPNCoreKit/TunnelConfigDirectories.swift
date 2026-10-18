//
//  TunnelConfigDirectories.swift
//  DVPNSDK
//

import Foundation
import Synchronization

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

    /// Root of the tunnel configuration files: inside the App Group container, or the directory a test named
    /// (`overrideHomeDirectory(_:)`).
    package static var homeDirectory: URL? {
        if let override = homeDirectoryOverride.withLock({ $0 }) {
            return try? createDirectory(at: override)
        }
        return appGroupHomeDirectory
    }

    /// Keeps the configuration files in `url` instead of the App Group container, which a test process cannot write.
    package static func overrideHomeDirectory(_ url: URL) {
        homeDirectoryOverride.withLock { $0 = url }
    }

    private static let homeDirectoryOverride = Mutex<URL?>(nil)

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
    static let dnsConfigurationKey = "DNS_CONFIGURATION"

    /// Hands the app's DNS choice to the proxy extensions, which read it back with `dnsConfiguration(in:)`.
    static func storeDNS(_ dns: DNSServerType, in defaults: UserDefaults = .shared) {
        storeDNS(dns.configuration, in: defaults)
    }

    /// Hands the app's resolvers to the proxy extensions, which read them back with `dnsConfiguration(in:)`. The
    /// servers alone go under `dnsKey` too, as earlier builds stored them (`dns(in:)`).
    static func storeDNS(_ dns: DNSConfiguration, in defaults: UserDefaults = .shared) {
        defaults.set(dns.servers, forKey: dnsKey)
        defaults.set(try? JSONEncoder().encode(dns), forKey: dnsConfigurationKey)
    }

    /// The resolvers for a proxy tunnel: the configuration the app stored or, from a build that stored servers only,
    /// those servers in plain DNS.
    static func dnsConfiguration(in defaults: UserDefaults = .shared) -> DNSConfiguration {
        if let data = defaults.data(forKey: dnsConfigurationKey),
           let configuration = try? JSONDecoder().decode(DNSConfiguration.self, from: data)
        {
            return configuration
        }
        return DNSConfiguration(name: "stored", servers: dns(in: defaults))
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

    static let networkKey = "NETWORK"

    /// Hands how a proxy tunnel routes (IPv6, for one) to the proxy extensions, which read it back with `network(in:)`.
    static func storeNetwork(_ network: NetworkModel, in defaults: UserDefaults = .shared) {
        defaults.set(try? JSONEncoder().encode(network), forKey: networkKey)
    }

    /// What a proxy tunnel runs with: what the app stored at its last start, or `NetworkModel.default` when it stored
    /// nothing (a build that predates it, which a system on-demand start can still find).
    static func network(in defaults: UserDefaults = .shared) -> NetworkModel {
        guard let data = defaults.data(forKey: networkKey),
              let network = try? JSONDecoder().decode(NetworkModel.self, from: data)
        else { return .default }
        return network
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
