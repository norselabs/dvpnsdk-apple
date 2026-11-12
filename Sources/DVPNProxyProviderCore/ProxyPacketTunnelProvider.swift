//
//  ProxyPacketTunnelProvider.swift
//  DVPNSDK
//

import DVPNCoreKit
import NetworkExtension
import os

// MARK: - ProxyPacketTunnelProvider

/// Shared plumbing for tunnel providers built on a local SOCKS5 proxy engine (Xray, Hysteria).
///
/// The provider claims a synthetic tunnel interface, asks the subclass to start its engine so a
/// SOCKS5 server listens on the start's `LocalProxy` (a free loopback port with random credentials), then
/// runs hev-socks5-tunnel (`Socks5Tunnel`) to pipe the utun packets into that proxy. Subclasses override
/// `startProxy(network:proxy:)` and `stopProxy()`.
open class ProxyPacketTunnelProvider: NEPacketTunnelProvider {
    open var mtu: Int { 9000 }

    /// Whether the app announced that the coming stop follows a failure (`ExtensionLogFile.failedStopNotice`).
    private let stopFollowsFailure = OSAllocatedUnfairLock(initialState: false)
    private let socks5TunnelLoop = Socks5TunnelLoop()

    override public init() {
        super.init()
    }

    /// Start the proxy engine; a SOCKS5 server must be listening on `proxy.listenAddress`, accepting only
    /// `proxy.username` and `proxy.password`, on return. Runs after the tunnel settings are applied; the
    /// provider's own connections bypass the tunnel, so an engine may talk to its server here (Xray probes the
    /// node for TLS before starting).
    open nonisolated(nonsending) func startProxy(network: NetworkModel, proxy: LocalProxy) async throws {
        throw NSError.newError("\(type(of: self)) does not implement startProxy(network:proxy:)")
    }

    /// Stop the proxy engine started by `startProxy(network:proxy:)`.
    open func stopProxy() {}

    /// The node this start connects to, which the split-tunnel proxy leaves out; nil when unknown.
    open var nodeHost: String? {
        nil
    }

    open func makeNetworkSettings(network: NetworkModel) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        settings.mtu = NSNumber(value: mtu)
        settings.ipv4Settings = {
            let settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
            settings.includedRoutes = [NEIPv4Route.default()]
            if network.hideVPNIcon {
                settings.excludedRoutes = [NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "255.0.0.0")]
            }
            return settings
        }()
        settings.ipv6Settings = {
            guard network.ipv6Enabled else {
                return nil
            }
            let settings = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
            settings.includedRoutes = [NEIPv6Route.default()]
            if network.hideVPNIcon {
                settings.excludedRoutes = [NEIPv6Route(destinationAddress: "::", networkPrefixLength: 128)]
            }
            return settings
        }()
        settings.dnsSettings = Self.dnsSettings(servers: TunnelConfigDirectories.dns())
        return settings
    }

    /// The tunnel's resolvers: DNS over HTTPS to the provider `servers` belong to, at one of its addresses
    /// (`DNSServerType.dnsOverHTTPSSettings(servers:in:)`). Servers of no provider keep plain DNS. A line in the log
    /// says which.
    static func dnsSettings(servers: [String], in defaults: UserDefaults = .shared) -> NEDNSSettings {
        guard let settings = DNSServerType.dnsOverHTTPSSettings(servers: servers, in: defaults) else {
            logger.notice("DNS: plain, the servers are of no provider")
            return NEDNSSettings(servers: servers)
        }
        logger.notice("DNS: over HTTPS at \(settings.serverURL?.host() ?? "no host", privacy: .public)")
        return settings
    }

    override open nonisolated(nonsending) func startTunnel(options: [String: NSObject]? = nil) async throws {
        ProxyStartErrorStore.clear()
        let network = NetworkModel.default
        let host = nodeHost
        logger.notice("\(NodeAddressStore.startLine(host: host), privacy: .public)")
        // On every platform, for `TunnelManager.connectedNode()`. Before the tunnel's interface appears, so the macOS
        // split-tunnel proxy sees both together.
        TunnelStateStore.record(isUp: true, server: host)

        do {
            try await setTunnelNetworkSettings(makeNetworkSettings(network: network))
            let proxy = try LocalProxy.random()
            try await startProxy(network: network, proxy: proxy)
            try startSocks5Tunnel(proxy: proxy)
        } catch {
            logger.error("starting tunnel failed due to: \(error.logDescription, privacy: .public)")
            // Only the error text is recorded, never the configuration.
            ProxyStartErrorStore.record(error.logDescription)
            TunnelStateStore.record(isUp: false)
            ExtensionLogFile.dump()
            throw error
        }
    }

    override open nonisolated(nonsending) func stopTunnel(with reason: NEProviderStopReason) async {
        socks5TunnelLoop.stop()
        logger.error("tunnel is stopped due to: \(Self.describe(reason), privacy: .public)")
        TunnelStateStore.record(isUp: false)
        stopProxy()
        if stopFollowsFailure.withLock({ $0 }) || ExtensionLogFile.isWritten(after: reason) {
            ExtensionLogFile.dump()
        }
    }

    /// Answers `ExtensionLogFile.failedStopNotice`, which makes the coming stop write the log file; any other message
    /// gets nil. A subclass that overrides this passes what it does not handle to `super`.
    override open nonisolated(nonsending) func handleAppMessage(_ messageData: Data) async -> Data? {
        guard messageData == ExtensionLogFile.failedStopNotice else { return nil }
        stopFollowsFailure.withLock { $0 = true }
        logger.info("The coming stop follows a failure: it writes the log file")
        return messageData
    }
}

// MARK: - Internal

extension ProxyPacketTunnelProvider {
#if os(macOS)
    static let maxSessionCount = sessionCap(onMacOS: true)
#else
    static let maxSessionCount = sessionCap(onMacOS: false)
#endif

    /// hev-socks5-tunnel's session cap, TCP and UDP together, 0 for none: the session that reaches it ends the least
    /// recently active one. iOS and tvOS cap at 100; macOS has no cap.
    static func sessionCap(onMacOS: Bool) -> Int {
        onMacOS ? 0 : 100
    }

    func startSocks5Tunnel(proxy: LocalProxy) throws {
        let config = Self.socks5TunnelConfiguration(mtu: mtu, proxy: proxy)
        let configurationFilePath = TunnelConfigDirectories.cachesDirectory
            .appending(component: "config.yml")
            .path(percentEncoded: false)
        guard FileManager.default.createFile(atPath: configurationFilePath, contents: Data(config.utf8)) else {
            throw NSError.newError("Tunnel failed to write configuration file")
        }
        guard let descriptor = Socks5Tunnel.tunnelFileDescriptor else {
            throw NSError.newError("Tunnel failed to find its utun interface")
        }
        // `nonisolated(unsafe)`: the provider is not Sendable, and the loop's thread only cancels the tunnel through it,
        // which writes stores and calls NetworkExtension, both safe from any thread.
        nonisolated(unsafe) weak var provider = self
        socks5TunnelLoop.start {
            Socks5Tunnel.run(configurationPath: configurationFilePath, descriptor: descriptor)
        } endedOnItsOwn: { exitCode in
            provider?.cancelTunnel(socks5TunnelExitCode: exitCode)
        }
    }

    /// hev-socks5-tunnel's YAML configuration.
    static func socks5TunnelConfiguration(mtu: Int, proxy: LocalProxy) -> String {
        // hev resets a TCP connection that carries nothing either way for 5 minutes, Xray's own idle limit, so a quiet
        // session (SSH without keepalives, a long poll) outlasts a minute; a UDP association ends after a quiet minute.
        """
        tunnel:
          mtu: \(mtu)
        socks5:
          port: \(proxy.port)
          address: \(LocalProxy.host)
          udp: 'udp'
          username: '\(proxy.username)'
          password: '\(proxy.password)'
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          log-file: stderr
          log-level: error
          limit-nofile: 65535
          max-session-count: \(maxSessionCount)
        """
    }

    /// Cancels the tunnel whose hev-socks5-tunnel loop ended on its own: nothing reads its packets any more, so it
    /// must not stay connected. As a failed start does, it records the tunnel down and writes the log file.
    func cancelTunnel(socks5TunnelExitCode exitCode: Int32) {
        logger.error("hev-socks5-tunnel stopped on its own with exit code \(exitCode, privacy: .public)")
        TunnelStateStore.record(isUp: false)
        ExtensionLogFile.dump()
        cancelTunnelWithError(NSError.newError("hev-socks5-tunnel stopped on its own with exit code \(exitCode)"))
    }

    static func describe(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none:
            return "No specific reason."
        case .userInitiated:
            return "The user stopped the provider."
        case .providerFailed:
            return "The provider failed."
        case .noNetworkAvailable:
            return "There is no network connectivity."
        case .unrecoverableNetworkChange:
            return "The device attached to a new network."
        case .providerDisabled:
            return "The provider was disabled."
        case .authenticationCanceled:
            return "The authentication process was cancelled."
        case .configurationFailed:
            return "The provider could not be configured."
        case .idleTimeout:
            return "The provider was idle for too long."
        case .configurationDisabled:
            return "The associated configuration was disabled."
        case .configurationRemoved:
            return "The associated configuration was deleted."
        case .superceded:
            return "A high-priority configuration was started."
        case .userLogout:
            return "The user logged out."
        case .userSwitch:
            return "The active user changed."
        case .connectionFailed:
            return "Failed to establish connection."
        case .sleep:
            return "The device went to sleep and disconnectOnSleep is enabled in the configuration."
        case .appUpdate:
            return "The NEProvider is being updated."
        case .internalError:
            return "An internal error occurred."
        @unknown default:
            return "Unknown reason."
        }
    }
}
