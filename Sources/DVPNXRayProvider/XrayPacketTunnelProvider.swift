//
//  XrayPacketTunnelProvider.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNProxyProviderCore
import DVPNXRayCore
import NetworkExtension
import os

// MARK: - XrayPacketTunnelProvider

/// Base packet tunnel provider for the Xray network extension.
/// The extension target only subclasses it:
/// `final class PacketTunnelProvider: XrayPacketTunnelProvider {}`
///
/// Xray-core runs in-process through libXray and exposes a SOCKS5 inbound that the shared
/// `ProxyPacketTunnelProvider` plumbing connects to the tunnel interface. The proxy outbound is
/// rendered from the typed model stored by the app (backend credentials). A V2RAY node's metadata does
/// not say whether it speaks TLS, so `XraySecurityResolver` handshakes with it first and pins the certificate it presents
/// (see `XSecurity.autodetect`).
open class XrayPacketTunnelProvider: ProxyPacketTunnelProvider {
    override public init() {
        super.init()
    }

    override open nonisolated(nonsending) func startProxy(network: NetworkModel, proxy: LocalProxy) async throws {
        do {
            let resolved: XConfigurationModel = switch try XraySourceStore.loadCurrent() {
            case let .model(model):
                await XraySecurityResolver.resolve(model)
            }
            if resolved.obfuscation.isEnabled {
                logger.info("Obfuscation on: TLS ClientHello fragmentation (\(resolved.obfuscation.mode.rawValue, privacy: .public))")
            }

            let assetDirectory = TunnelConfigDirectories.assetDirectory?.path(percentEncoded: false)
            let document = try XrayDocumentBuilder.build(
                proxyOutbound: try resolved.proxyOutbound(),
                supportingOutbounds: try resolved.supportingOutbounds(),
                localProxy: proxy,
                assetDirectory: assetDirectory
            )

            logger.info("Starting Xray-core \((try? XrayInvoke.xrayVersion()) ?? "unknown", privacy: .public)")
            try XrayInvoke.runXray(configJSON: String(decoding: document, as: UTF8.self))
        } catch {
            // libXray's errors are generic by design; the provider records this text for the app's log.
            throw NSError.newError("Xray failed to start: \(error.localizedDescription)")
        }
    }

    override open func stopProxy() {
        do {
            try XrayInvoke.stopXray()
        } catch {
            logger.error("Xray failed to stop: \(error.localizedDescription, privacy: .public)")
        }
    }
}
