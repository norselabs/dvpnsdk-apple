//
//  HysteriaPacketTunnelProvider.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNProxyProviderCore
import NetworkExtension
import os

// MARK: - HysteriaPacketTunnelProvider

/// Base packet tunnel provider for the Hysteria 2 network extension.
/// The extension target only subclasses it:
/// `final class PacketTunnelProvider: HysteriaPacketTunnelProvider {}`
///
/// The Hysteria client runs in-process through libhysteria and exposes a SOCKS5 server that the
/// shared `ProxyPacketTunnelProvider` plumbing connects to the tunnel interface.
open class HysteriaPacketTunnelProvider: ProxyPacketTunnelProvider {
    override public init() {
        super.init()
    }

    override open var nodeHost: String? {
        try? HysteriaConfigurationStore.loadCurrent().server
    }

    override open nonisolated(nonsending) func startProxy(network: NetworkModel, proxy: LocalProxy) async throws {
        var configuration = try HysteriaConfigurationStore.loadCurrent()
        configuration.socks5 = .local(proxy)

        logger.info("Starting libhysteria \(HysteriaBridge.version(), privacy: .public)")
        try HysteriaBridge.start(configJSON: try configuration.jsonString())
    }

    override open func stopProxy() {
        do {
            try HysteriaBridge.stop()
        } catch {
            logger.error("Hysteria failed to stop: \(error.localizedDescription, privacy: .public)")
        }
    }
}
