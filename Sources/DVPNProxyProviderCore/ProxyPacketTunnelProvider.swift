//
//  ProxyPacketTunnelProvider.swift
//  DVPNSDK
//

import DVPNCoreKit
import NetworkExtension
import os
import Synchronization

// MARK: - ProxyPacketTunnelProvider

/// Shared plumbing for tunnel providers built on a local SOCKS5 proxy engine (Xray, Hysteria).
///
/// The provider claims a synthetic tunnel interface, asks the subclass to start its engine so a
/// SOCKS5 server listens on the start's `LocalProxy` (a free loopback port with random credentials), then
/// runs hev-socks5-tunnel (`Socks5Tunnel`) to pipe the utun packets into that proxy. Subclasses override
/// `startProxy(network:proxy:)` and `stopProxy()`. A node switch (`TunnelProviderMessage.switchNode`) stops and
/// starts the engine alone, on the same local proxy.
open class ProxyPacketTunnelProvider: NEPacketTunnelProvider {
    open var mtu: Int { 9000 }

    /// What the running tunnel started with, which a node switch keeps; nil while it is down.
    private let running = Mutex<RunningTunnel?>(nil)

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
        Self.networkSettings(network: network, mtu: mtu, dns: TunnelConfigDirectories.dnsConfiguration())
    }

    /// Every IPv4 route into the tunnel and, when `network` enables IPv6, every IPv6 route too, from a unique local
    /// address: hev-socks5-tunnel hands IPv6 connections to the engine like IPv4 ones, and without IPv6 settings the
    /// system would send IPv6 around the tunnel. DNS over HTTPS when `dns` has a DoH URL, plain DNS otherwise.
    static func networkSettings(network: NetworkModel, mtu: Int, dns: DNSConfiguration) -> NEPacketTunnelNetworkSettings {
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
        settings.dnsSettings = dns.dnsSettings(includingIPv6: network.ipv6Enabled)
        return settings
    }

    override open nonisolated(nonsending) func startTunnel(options: [String: NSObject]? = nil) async throws {
        ProxyStartErrorStore.clear()
        let network = TunnelConfigDirectories.network()
        // On every platform, for `TunnelManager.connectedNode()`. Before the tunnel's interface appears, so the macOS
        // split-tunnel proxy sees both together.
        TunnelStateStore.record(isUp: true, server: nodeHost)

        do {
            let dns = TunnelConfigDirectories.dnsConfiguration()
            try await setTunnelNetworkSettings(makeNetworkSettings(network: network))
            let proxy = try LocalProxy.random()
            try await startProxy(network: network, proxy: proxy)
            try startSocks5Tunnel(proxy: proxy)
            running.withLock { $0 = RunningTunnel(network: network, proxy: proxy, dns: dns) }
        } catch {
            logger.error("starting tunnel failed due to: \(error, privacy: .public)")
            // Only the error text is recorded, never the configuration.
            ProxyStartErrorStore.record(error.logDescription)
            TunnelStateStore.record(isUp: false)
            ExtensionLogFile.dump()
            throw error
        }
    }

    override open nonisolated(nonsending) func stopTunnel(with reason: NEProviderStopReason) async {
        logger.error("tunnel is stopped due to: \(Self.describe(reason), privacy: .public)")
        running.withLock { $0 = nil }
        TunnelStateStore.record(isUp: false)
        stopProxy()
        ExtensionLogFile.dump()
    }

    override open nonisolated(nonsending) func handleAppMessage(_ messageData: Data) async -> Data? {
        guard TunnelProviderMessage(messageData) == .switchNode else { return nil }
        return await switchNode().data
    }

    /// Restarts the engine alone on the configuration the app stored: the tunnel interface, its routes and
    /// hev-socks5-tunnel stay, and the engine listens on the same local proxy again, so until it does, connections into
    /// the tunnel fail inside it instead of going around it. A DNS change the app stored with the node applies too; the
    /// routes, IPv6 included, stay as the tunnel started. When the engine cannot start on the new node, the tunnel stays
    /// up without one, carrying nothing, until the app switches again or stops it.
    nonisolated(nonsending) func switchNode() async -> NodeSwitchReply {
        let tunnel: RunningTunnel? = running.withLock { state in
            guard let current = state, !current.isSwitching else { return nil }
            state?.isSwitching = true
            return current
        }
        guard let tunnel else {
            logger.error("Switching node refused: the tunnel is not running, or is switching already")
            return .failed("The tunnel is not running, or is switching nodes already")
        }
        defer { running.withLock { $0?.isSwitching = false } }

        reasserting = true
        defer { reasserting = false }
        stopProxy()
        TunnelStateStore.record(isUp: true, server: nodeHost)
        do {
            let dns = TunnelConfigDirectories.dnsConfiguration()
            if dns != tunnel.dns {
                try await setTunnelNetworkSettings(makeNetworkSettings(network: tunnel.network))
                running.withLock { $0?.dns = dns }
            }
            try await startProxy(network: tunnel.network, proxy: tunnel.proxy)
            logger.info("Switched node in place")
            return .switched
        } catch {
            logger.error("Switching node failed: \(error, privacy: .public)")
            ExtensionLogFile.dump()
            return .failed(error.logDescription)
        }
    }
}

// MARK: - RunningTunnel

/// What a node switch keeps of a running proxy tunnel: hev-socks5-tunnel goes on forwarding to `proxy`.
struct RunningTunnel: Sendable {
    let network: NetworkModel
    let proxy: LocalProxy
    /// The resolvers the tunnel's settings carry, so that a switch reapplies them only when the app changed them.
    var dns: DNSConfiguration
    var isSwitching = false
}

// MARK: - Internal

extension ProxyPacketTunnelProvider {
    func startSocks5Tunnel(proxy: LocalProxy) throws {
        let config = """
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
          read-write-timeout: 60000
          log-file: stderr
          log-level: error
          limit-nofile: 65535
        """
        let configurationFilePath = TunnelConfigDirectories.cachesDirectory
            .appending(component: "config.yml")
            .path(percentEncoded: false)
        guard FileManager.default.createFile(atPath: configurationFilePath, contents: Data(config.utf8)) else {
            throw NSError.newError("Tunnel failed to write configuration file")
        }
        guard let descriptor = Socks5Tunnel.tunnelFileDescriptor else {
            throw NSError.newError("Tunnel failed to find its utun interface")
        }
        // hev-socks5-tunnel's main loop blocks until the tunnel stops, so it gets a thread of its own
        // instead of a cooperative-pool thread.
        let thread = Thread {
            let exitCode = Socks5Tunnel.run(configurationPath: configurationFilePath, descriptor: descriptor)
            logger.info("hev-socks5-tunnel exited with \(exitCode, privacy: .public)")
        }
        thread.name = "io.norselabs.dvpn.hev-socks5-tunnel"
        thread.qualityOfService = .userInitiated
        thread.start()
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
