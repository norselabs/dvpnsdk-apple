//
//  TunnelManager.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNSDK
import DVPNWireGuardCore
import DVPNXRayCore
import Foundation
import WireGuardKit

// MARK: - Constants

private struct Constants {
    let persistentKeepAlive = "25"
    let allowedIPs = "0.0.0.0/0"
}

private let constants = Constants()

// MARK: - TunnelManager

/// App-facing entry point of the tunnel layer.
///
/// All work happens on the main actor. The underlying `TunnelsService` is created lazily on first
/// use, so the manager can be constructed anywhere (e.g. as a global) and NetworkExtension is only
/// touched after `DVPNCore.bootstrap`.
@MainActor
public final class TunnelManager {
    private var tunnelModel = TunnelModel(tunnelConfiguration: nil)
    let storage: any TunnelSettingsProviding
    let configuration: DVPNCoreConfiguration

    private var service: TunnelsService?
    private var serviceCreation: Task<TunnelsService, any Error>?
    private var eventForwarding: Task<Void, Never>?
    private let broadcaster = EventBroadcaster<TunnelEvent>(initial: .status(.disconnected))

    public nonisolated init(
        settings: any TunnelSettingsProviding,
        configuration: DVPNCoreConfiguration
    ) {
        storage = settings
        self.configuration = configuration
    }
}

// MARK: - Status

extension TunnelManager {
    var lastTunnel: TunnelContainer? {
        service?.tunnels.last
    }

    /// Synchronous snapshot; `false` until the service has been loaded. Prefer `isActive()`.
    var isTunnelActive: Bool {
        service?.tunnels.last?.status == .connected
    }

    public func isActive() async -> Bool {
        (try? await loadService())?.tunnels.last?.status == .connected
    }

    /// Waits until the connected tunnel can carry traffic (WireGuard: first handshake done;
    /// Xray: immediately). Returns `false` when not connected or after `timeout`.
    public func waitUntilReady(timeout: Duration = .seconds(10)) async -> Bool {
        guard let tunnel = (try? await loadService())?.tunnels.last else { return false }
        return await tunnel.waitUntilReady(timeout: timeout)
    }

    /// Loads the tunnel service ahead of the first `start`/`stop`.
    func prepare() async throws(TunnelsServiceError) {
        _ = try await loadService()
    }

    /// Status and error events of the managed tunnel. Starts with the latest known status.
    public nonisolated func events() -> AsyncStream<TunnelEvent> {
        broadcaster.subscribe()
    }
}

// MARK: - Start / stop

extension TunnelManager {
    /// Starts the tunnel engine that serves the credentials' node type. Returns once connected (and,
    /// for the WireGuard family, once the first handshake is seen).
    public func start(from credentials: ConnectionCredentials) async throws(TunnelsServiceError) {
        switch credentials.nodeType.tunnelProtocolID {
        case .wireGuard:
            try await startWireguard(from: credentials)
        case .xray:
            try await startXray(from: credentials)
        case .hysteria:
            try await startHysteria(from: credentials)
        }
    }

    /// Disables on-demand and stops the managed tunnel. Returns once it is disconnected.
    public func stop() async throws(TunnelsServiceError) {
        let service = try await loadService()
        await service.startDeactivationOfActiveTunnel()
    }

    func startActivation(of tunnel: TunnelContainer) async throws(TunnelsServiceError) {
        let service = try await loadService()
        try await service.set(onDemandEnabled: true, for: tunnel)
        try await activate(tunnel, in: service)
    }

    func startDeactivation(of tunnel: TunnelContainer) async throws(TunnelsServiceError) {
        let service = try await loadService()
        try await service.set(onDemandEnabled: false, for: tunnel)
        await service.startDeactivation(of: tunnel)
    }
}

// MARK: - WireGuard

extension TunnelManager {
    func startWireguard(from credentials: ConnectionCredentials) async throws(TunnelsServiceError) {
        let service = try await loadService()

        if tunnelModel.peersModel.isEmpty { throw .emptyCredentials }

        guard let rawKey = credentials.privateKey, let privateKey = PrivateKey(base64Key: rawKey) else {
            throw .emptyCredentials
        }
        // AmneziaWG is WireGuard plus extra `[Interface]` parameters; both run in the WireGuard extension.
        let wg: WireGuardEndpoint
        let amneziaParameters: [String: String]
        switch credentials.endpoint {
        case let .wireGuard(endpoint):
            wg = endpoint
            amneziaParameters = [:]
        case let .amneziaWG(endpoint):
            wg = endpoint.wireGuard
            // Nodes send the handshake-affecting S/H/I values only; junk packets are our choice.
            amneziaParameters = AmneziaWGJunkDefaults.filling(endpoint.parameters)
        case .v2ray, .xrayNode, .hysteria:
            throw .emptyCredentials
        }

        Self.configureBackendNode(tunnelModel, privateKey: privateKey, endpoint: wg, dns: storage.selectedDNS.address)

        let tunnelConfiguration: TunnelConfiguration
        switch tunnelModel.save() {
        case let .failure(error):
            throw .addTunnelFailed(systemError: error)
        case let .success(configuration):
            do {
                tunnelConfiguration = try configuration.applyingAmneziaWG(amneziaParameters)
            } catch {
                logger.error("Invalid AmneziaWG parameters: \(error, privacy: .public)")
                throw .addTunnelFailed(systemError: error)
            }
        }

        let tunnel: TunnelContainer
        if let existing = service.tunnels.last {
            try await service.modify(
                tunnel: existing,
                isOnDemandEnabled: true,
                tunnelConfiguration: tunnelConfiguration
            )
            tunnel = existing
        } else {
            tunnel = try await service.add(tunnelConfiguration: tunnelConfiguration, onDemandEnabled: true)
        }

        try await activate(tunnel, in: service)
    }
}

// MARK: - Backend WireGuard node

extension TunnelManager {
    /// Writes a backend WireGuard node into `model`. The model is seeded from the last stored
    /// configuration (possibly another node type), so every field the backend does not provide is cleared
    /// here: a leftover preshared key, for one, makes the server accept our handshake initiation but
    /// makes us reject its response ("Received invalid response message"), i.e. a tunnel that never handshakes.
    static func configureBackendNode(_ model: TunnelModel, privateKey: PrivateKey, endpoint wg: WireGuardEndpoint, dns: String) {
        model.interfaceModel[.privateKey] = privateKey.base64Key
        model.interfaceModel[.publicKey] = privateKey.publicKey.base64Key
        model.interfaceModel[.dns] = dns
        model.interfaceModel[.addresses] = "\(wg.clientAddress)/32"
        model.interfaceModel[.mtu] = ""

        let port = String(wg.port)
        model.interfaceModel[.listenPort] = port
        model.peersModel[0][.endpoint] = "\(wg.host):\(port)"
        model.peersModel[0][.publicKey] = wg.peerPublicKey
        model.peersModel[0][.preSharedKey] = ""
        model.peersModel[0][.allowedIPs] = constants.allowedIPs
        model.peersModel[0][.persistentKeepAlive] = constants.persistentKeepAlive
    }
}

// MARK: - XRAY

extension TunnelManager {
    /// Both Xray node types end in the same typed model; each selection rule set is the node type's own.
    func startXray(from credentials: ConnectionCredentials) async throws(TunnelsServiceError) {
        guard let uid = credentials.uid else {
            throw .emptyCredentials
        }
        var model: XConfigurationModel
        switch credentials.endpoint {
        case let .v2ray(node):
            do {
                model = try V2RayNodeSelection.model(for: node, uuid: uid)
            } catch {
                logger.error("V2RAY node \(node.host, privacy: .public) offers no inbound this client can use: \(error, privacy: .public)")
                throw .emptyCredentials
            }
        case let .xrayNode(node):
            do {
                model = try XrayNodeSelection.model(for: node, uuid: uid)
            } catch {
                logger.error("XRAY node \(node.host, privacy: .public) offers no inbound this client can use")
                throw .emptyCredentials
            }
        case .wireGuard, .amneziaWG, .hysteria:
            throw .emptyCredentials
        }
        model.obfuscation = selectedObfuscation
        try await startXray(source: .model(model), descriptor: try requiredDescriptor(for: .xray))
    }

    /// The app's "Advanced obfuscation" setting, read at connect time so a toggle applies to the next connection.
    var selectedObfuscation: XObfuscation {
        storage.isObfuscationEnabled ? .tlsFragment(.init()) : .none
    }

    /// Stores the source in the App Group and activates the Xray tunnel.
    func startXray(source: XraySource, descriptor: TunnelProtocolDescriptor) async throws(TunnelsServiceError) {
        let service = try await loadService()
        TunnelConfigDirectories.storeDNS(storage.selectedDNS)
        do {
            try XraySourceStore.save(source)
        } catch {
            logger.error("Failed to store Xray configuration: \(error, privacy: .public)")
            throw .addTunnelFailed(systemError: error)
        }
        let tunnel = try await service.startProxyTunnel(descriptor, onDemandEnabled: true)
        try await activate(tunnel, in: service)
    }
}

// MARK: - Private

extension TunnelManager {
    /// The app-declared descriptor for `id`, or `.unsupportedProtocol` when this app does not ship it.
    func requiredDescriptor(for id: TunnelProtocolID) throws(TunnelsServiceError) -> TunnelProtocolDescriptor {
        guard let descriptor = configuration.descriptor(for: id) else {
            logger.error("Protocol \(id.rawValue, privacy: .public) is not declared by this app")
            throw .unsupportedProtocol
        }
        return descriptor
    }
}

extension TunnelManager {
    func loadService() async throws(TunnelsServiceError) -> TunnelsService {
        if let service { return service }

        let creation = serviceCreation ?? Task { try await TunnelsService.create() }
        serviceCreation = creation

        let created: TunnelsService
        do {
            created = try await creation.value
        } catch let error as TunnelsServiceError {
            serviceCreation = nil
            throw error
        } catch {
            serviceCreation = nil
            throw .loadTunnelsFailed(systemError: error)
        }

        if service == nil {
            attach(created)
        }
        return created
    }

    func attach(_ service: TunnelsService) {
        self.service = service
        service.refreshStatuses()
        // A config written by an older app version (pre-XraySource) cannot decode; drop it, the next connect rewrites it.
        XraySourceStore.removeIfUnreadable()

        if let tunnel = service.tunnels.last {
            tunnelModel = TunnelModel(tunnelConfiguration: tunnel.tunnelConfiguration)
        }
        prepareTunnelModel()

        eventForwarding = Task { [weak self] in
            for await event in service.events() {
                guard let self else { return }
                if case .error = event {
                    broadcaster.send(event, remember: false)
                } else {
                    broadcaster.send(event)
                }
            }
        }
        logger.info("Tunnel service created.")
    }

    func prepareTunnelModel() {
        tunnelModel.interfaceModel[.name] = configuration.requiredDescriptor(for: .wireGuard).tunnelName
        if tunnelModel.peersModel.isEmpty {
            tunnelModel.appendEmptyPeer()
        }
        tunnelModel.peersModel[0][.allowedIPs] = constants.allowedIPs
        tunnelModel.peersModel[0][.persistentKeepAlive] = constants.persistentKeepAlive
    }

    /// How long a WireGuard-family tunnel may stay `.connected` without a handshake before the
    /// connection attempt is declared failed (the engine retries the handshake every 5 s).
    static let handshakeTimeout: Duration = .seconds(10)

    func activate(_ tunnel: TunnelContainer, in service: TunnelsService) async throws(TunnelsServiceError) {
        let isProxyEngine = tunnel.descriptor?.id == .xray || tunnel.descriptor?.id == .hysteria
        if isProxyEngine { ProxyStartErrorStore.clear() }
        do {
            try await service.startActivation(of: tunnel)
        } catch {
            var error = error
            // The extension cannot return its error text through NetworkExtension; it leaves it in the App Group.
            if isProxyEngine, let recorded = ProxyStartErrorStore.load() {
                error = .startingFailed(systemError: NSError.newError(recorded.message))
            }
            // Every connect saved the profile with on-demand on. A start that failed must not leave the
            // system retrying it in the background while the app shows "disconnected", and one that timed
            // out may still be connecting: stop both, as the handshake timeout below does.
            try? await service.set(onDemandEnabled: false, for: tunnel)
            await service.startDeactivation(of: tunnel)
            broadcaster.send(.error(error), remember: false)
            throw .activationFailed(error)
        }

        // `.connected` only means the provider started. A WireGuard/AmneziaWG tunnel with wrong keys or a
        // dead peer stays "connected" forever without carrying traffic, so require the first handshake
        // here and fail fast instead of leaving the app verifying a tunnel that will never work.
        // Only a *positively observed* absence counts: if the extension cannot report its runtime
        // configuration, the tunnel is left running rather than torn down on a blind diagnostic.
        guard tunnel.descriptor?.readiness == .wireGuardHandshake else { return }
        switch await tunnel.readiness(timeout: Self.handshakeTimeout) {
        case .completed:
            return
        case let .unavailable(reason):
            logger.warning("Cannot verify the handshake for '\(tunnel.name, privacy: .public)' (\(reason, privacy: .public)); keeping the tunnel")
            return
        case .timedOut:
            logger.error("No handshake within \(Self.handshakeTimeout) for '\(tunnel.name, privacy: .public)'; stopping")
            try? await service.set(onDemandEnabled: false, for: tunnel)
            await service.startDeactivation(of: tunnel)
            let error = TunnelActivationError.handshakeTimedOut
            broadcaster.send(.error(error), remember: false)
            throw .activationFailed(error)
        }
    }
}
