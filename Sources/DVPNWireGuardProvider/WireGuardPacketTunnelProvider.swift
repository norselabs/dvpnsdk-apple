//
//  WireGuardPacketTunnelProvider.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNWireGuardCore
import Foundation
import NetworkExtension
import os
import WireGuardKit

/// Base packet tunnel provider for the WireGuard network extension.
/// The extension target only subclasses it:
/// `final class PacketTunnelProvider: WireGuardPacketTunnelProvider {}`
open class WireGuardPacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter: WireGuardAdapter = .init(with: self) { [weak self] logLevel, message in
        self?.adapterLog(level: logLevel, message: message)
    }

    /// Redirect adapter log lines by overriding this in a subclass.
    open func adapterLog(level: WireGuardLogLevel, message: String) {
        // Info, not debug: these lines (resolved endpoint, network settings, backend handle, first
        // handshake, Go engine errors) are the only view into the engine without attaching a debugger.
        switch level {
        case .error:
            logger.error("Adapter: \(message, privacy: .public)")
        default:
            logger.info("Adapter: \(message, privacy: .public)")
        }
    }

    override open nonisolated(nonsending) func startTunnel(options: [String: NSObject]? = nil) async throws {
        logger.debug("PacketTunnelProvider: Starting tunnel with file-based storage")
        let activationAttemptId = options?["activationAttemptId"] as? String

        logger.info("Starting tunnel from the: \(activationAttemptId == nil ? "OS directly" : "app")")

        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            logger.error("Protocol configuration is not NETunnelProviderProtocol")
            throw PacketTunnelProviderError.savedProtocolConfigurationIsInvalid
        }

        // This will now load from file storage if available
        guard let tunnelConfiguration = tunnelProviderProtocol.asTunnelConfiguration() else {
            logger.error("failed due to: \(PacketTunnelProviderError.savedProtocolConfigurationIsInvalid, privacy: .public)")
            throw PacketTunnelProviderError.savedProtocolConfigurationIsInvalid
        }

#if os(macOS)
        // Before the tunnel's interface appears, so the split-tunnel proxy sees both together.
        TunnelStateStore.record(isUp: true)
#endif
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                adapter.start(tunnelConfiguration: tunnelConfiguration) { adapterError in
                    if let adapterError {
                        continuation.resume(throwing: adapterError)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
#if os(macOS)
            TunnelStateStore.record(isUp: false)
#endif
            if let adapterError = error as? WireGuardAdapterError { throw Self.map(adapterError) }
            throw error
        }

        logger.info("Tunnel interface is \(self.adapter.interfaceName ?? "unknown")")
    }

    override open nonisolated(nonsending) func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("Stopping tunnel")
#if os(macOS)
        TunnelStateStore.record(isUp: false)
#endif

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            adapter.stop { error in
                if let error {
                    logger.error("Failed to stop WireGuard adapter: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    override open nonisolated(nonsending) func handleAppMessage(_ messageData: Data) async -> Data? {
        guard messageData.count == 1, messageData[0] == 0 else { return nil }

        let settings = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            adapter.getRuntimeConfiguration { continuation.resume(returning: $0) }
        }
        return settings?.data(using: .utf8)
    }

    private static func map(_ error: WireGuardAdapterError) -> PacketTunnelProviderError {
        switch error {
        case .cannotLocateTunnelFileDescriptor:
            logger.error("Starting tunnel failed: could not determine file descriptor")
            return .couldNotDetermineFileDescriptor

        case let .dnsResolution(dnsErrors):
            let hostnamesWithDnsResolutionFailure = dnsErrors.map(\.address)
                .joined(separator: ", ")
            logger.error("DNS resolution failed for the following hostnames: \(hostnamesWithDnsResolutionFailure, privacy: .public)")
            return .dnsResolutionFailure

        case let .setNetworkSettings(error):
            logger.error("Starting tunnel failed with setTunnelNetworkSettings returning \(error.localizedDescription, privacy: .public)")
            return .couldNotSetNetworkSettings

        case let .startWireGuardBackend(errorCode):
            logger.error("Starting tunnel failed with wgTurnOn returning \(errorCode, privacy: .public)")
            return .couldNotStartBackend

        case .invalidState:
            logger.error("Starting tunnel failed: adapter is already started")
            return .adapterInvalidState
        }
    }
}
