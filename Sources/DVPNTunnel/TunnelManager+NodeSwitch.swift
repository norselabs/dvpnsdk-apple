//
//  TunnelManager+NodeSwitch.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNSDK
import DVPNWireGuardCore
import DVPNXRayCore
import Foundation

// MARK: - Node switch

public extension TunnelManager {
    /// Connects the tunnel to the node in `credentials`, inside the running tunnel when it can, as a failover does.
    ///
    /// When the tunnel is up on the engine that serves the credentials (WireGuard for WireGuard and AmneziaWG nodes, Xray
    /// for Xray and V2Ray, Hysteria), its extension changes nodes in place: the tunnel interface and its routes stay, so
    /// the device's traffic waits for the new node instead of going around the tunnel. The WireGuard extension updates
    /// its running engine (`WireGuardAdapter.update`); the Xray and Hysteria extensions restart their engine alone, behind
    /// the same hev-socks5-tunnel. The DNS and obfuscation settings apply as they are now; the network options
    /// (`TunnelNetworkOptions`) stay as the tunnel started, until `restart()`.
    ///
    /// Otherwise (the tunnel is down, another engine runs, or the extension predates node switching) the tunnel stops
    /// and starts again from `credentials`, as `start(from:)` does. Between the two, the system may route traffic around
    /// the tunnel.
    ///
    /// Returns once the new node carries traffic (WireGuard: its first handshake). When it does not answer in time
    /// (`.activationFailed(.handshakeTimedOut)`) or the engine cannot start on it (`.activationFailed(.startingFailed)`),
    /// an in-place switch leaves the tunnel up, holding the traffic: switch to another node, or `stop()`. Calls must not
    /// overlap.
    func switchNode(to credentials: ConnectionCredentials) async throws(TunnelsServiceError) {
        let service = try await loadService()
        let engine = credentials.nodeType.tunnelProtocolID
        if let tunnel = service.tunnels.last, tunnel.status == .connected, runningEngine(of: tunnel) == engine {
            if try await switchInPlace(tunnel, to: credentials, engine: engine) { return }
            logger.info("The \(engine.rawValue, privacy: .public) extension cannot switch nodes in place; starting the tunnel again")
        }
        await service.startDeactivationOfActiveTunnel()
        try await start(from: credentials)
    }
}

// MARK: - Private

private extension TunnelManager {
    /// The engine of the extension the tunnel's profile points at, as this app declares it.
    func runningEngine(of tunnel: TunnelContainer) -> TunnelProtocolID? {
        configuration.descriptor(forProviderBundleID: tunnel.tunnelProvider.provider?.providerBundleIdentifier)?.id
    }

    /// Stores the node's configuration where the running extension reads it and asks the extension to switch to it.
    /// `false` when the extension does not know how.
    func switchInPlace(
        _ tunnel: TunnelContainer,
        to credentials: ConnectionCredentials,
        engine: TunnelProtocolID
    ) async throws(TunnelsServiceError) -> Bool {
        do {
            switch engine {
            case .wireGuard:
                let tunnelConfiguration = try wireGuardConfiguration(from: credentials)
                try WireGuardFileStorage.save(tunnelConfiguration: tunnelConfiguration, named: tunnelConfiguration.name ?? tunnel.name)
            case .xray:
                let model = try xrayModel(from: credentials)
                TunnelConfigDirectories.storeDNS(storage.dnsConfiguration)
                try XraySourceStore.save(.model(model))
            case .hysteria:
                guard case let .hysteria(endpoint) = credentials.endpoint else { throw TunnelsServiceError.emptyCredentials }
                TunnelConfigDirectories.storeDNS(storage.dnsConfiguration)
                try HysteriaConfigurationStore.save(Self.configuration(for: endpoint, uid: credentials.uid))
            }
        } catch let error as TunnelsServiceError {
            throw error
        } catch {
            logger.error("Failed to store the node to switch to: \(error, privacy: .public)")
            throw .addTunnelFailed(systemError: error)
        }

        switch await askToSwitchNode(tunnel) {
        case nil:
            return false
        case .switched:
            break
        case let .failed(reason):
            logger.error("The extension could not switch nodes: \(reason, privacy: .public)")
            let error = TunnelActivationError.startingFailed(systemError: NSError.newError(reason))
            broadcaster.send(.error(error), remember: false)
            throw .activationFailed(error)
        }

        guard engine == .wireGuard else { return true }
        // As at a start, the new peer must complete a handshake; only a positively observed absence counts.
        switch await tunnel.readinessAfterNodeSwitch(timeout: Self.handshakeTimeout) {
        case .completed:
            return true
        case let .unavailable(reason):
            logger.warning("Cannot verify the new node's handshake for '\(tunnel.name, privacy: .public)' (\(reason, privacy: .public))")
            return true
        case .timedOut:
            logger.error("No handshake with the new node within \(Self.handshakeTimeout); the tunnel stays up holding traffic")
            let error = TunnelActivationError.handshakeTimedOut
            broadcaster.send(.error(error), remember: false)
            throw .activationFailed(error)
        }
    }

    /// The extension's answer to `TunnelProviderMessage.switchNode`; nil when it gave none (an extension built before
    /// node switching) or could not be asked.
    func askToSwitchNode(_ tunnel: TunnelContainer) async -> NodeSwitchReply? {
        do {
            return try await tunnel.tunnelProvider.sendProviderMessage(TunnelProviderMessage.switchNode.data).flatMap(NodeSwitchReply.init)
        } catch {
            logger.error("Asking the extension to switch nodes failed: \(error, privacy: .public)")
            return nil
        }
    }
}
