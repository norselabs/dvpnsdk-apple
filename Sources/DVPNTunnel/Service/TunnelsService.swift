//
//  TunnelsService.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNWireGuardCore
import Foundation
import NetworkExtension
import WireGuardKit

@MainActor
final class TunnelsService {
    private(set) var tunnels: [TunnelContainer]

    /// How long `startActivation(of:)` waits for `.connected` before failing with `.timedOut`.
    var activationTimeout: Duration = .seconds(30)
    /// How long `startDeactivation(of:)` waits for `.disconnected`.
    var deactivationTimeout: Duration = .seconds(10)

    private let broadcaster = EventBroadcaster<TunnelEvent>()

    private var statusObservation: Task<Void, Never>?
    private var configurationObservation: Task<Void, Never>?
    private var pendingReload: Task<Void, Never>?
    /// Configuration-change notifications caused by our own writes are ignored until this instant.
    private var ignoreConfigurationChangesUntil: ContinuousClock.Instant = .now
    private let clock: any Clock<Duration>
    private let store: any TunnelProfileStore

    /// `clock` drives every wait in the service and its containers, and `store` loads and creates the profiles;
    /// tests pass an immediate clock and a fake store.
    init(
        tunnelProviders: [any TunnelProfile],
        store: any TunnelProfileStore = SystemTunnelProfileStore(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.clock = clock
        self.store = store
        tunnels = tunnelProviders
            .map { TunnelContainer(tunnel: $0, clock: clock) }
            .sorted { TunnelsService.nameIsLess(lhs: $0.name, than: $1.name) }
        tunnels.forEach(attach)

        startObservingTunnelStatuses()
        startObservingTunnelConfigurations()
        publishStatus()
    }

    static func nameIsLess(lhs: String, than rhs: String) -> Bool {
        lhs.compare(
            rhs,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive, .numeric]
        ) == .orderedAscending
    }

    /// Status and error events for the managed tunnel. Every call returns an independent stream
    /// that starts with the latest known status.
    nonisolated func events() -> AsyncStream<TunnelEvent> {
        broadcaster.subscribe()
    }
}

// MARK: - Creation

extension TunnelsService {
    static func create(
        store: any TunnelProfileStore = SystemTunnelProfileStore(),
        clock: any Clock<Duration> = ContinuousClock()
    ) async throws(TunnelsServiceError) -> TunnelsService {
        let managers: [any TunnelProfile]
        do {
            managers = try await store.loadAllProfiles()
        } catch {
            logger.error("Failed to get tunnel manager: \(error, privacy: .public)")
            throw .loadTunnelsFailed(systemError: error)
        }

        // Proxy engines keep no per-tunnel configuration reference, nothing to verify.
        if managers.first?.provider?.tunnelDescriptor?.readiness == .immediate {
            return TunnelsService(tunnelProviders: managers, store: store, clock: clock)
        }
        return TunnelsService(tunnelProviders: await cleanUpOrphaned(managers), store: store, clock: clock)
    }

    /// Drops tunnels whose stored configuration file no longer exists.
    private static func cleanUpOrphaned(
        _ managers: [any TunnelProfile]
    ) async -> [any TunnelProfile] {
        var kept: [any TunnelProfile] = []
        for manager in managers {
            if let provider = manager.provider, !provider.hasStoredConfiguration() {
                logger.info(
                    """
                    Removing orphaned tunnel with invalid configuration: \
                    \(manager.localizedDescription ?? "<unknown>")
                    """
                )
                do {
                    try await manager.removeFromPreferences()
                } catch {
                    logger.error("Failed to remove orphaned tunnel: \(error, privacy: .public)")
                }
            } else {
                kept.append(manager)
            }
        }
        return kept
    }
}

// MARK: - Adding & modifying

extension TunnelsService {
    /// Points the managed tunnel at a proxy-engine extension (Xray, Hysteria). Those providers
    /// read their configuration from the App Group on start, so the provider protocol carries
    /// only the extension identity.
    func startProxyTunnel(
        _ descriptor: TunnelProtocolDescriptor,
        onDemandEnabled: Bool
    ) async throws(TunnelsServiceError) -> TunnelContainer {
        let existing = tunnels.last
        let manager = existing?.tunnelProvider ?? store.makeProfile()

        manager.localizedDescription = descriptor.tunnelName
        manager.protocolConfiguration = {
            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.providerBundleIdentifier = descriptor.providerBundleID
            protocolConfiguration.serverAddress = descriptor.tunnelName
            protocolConfiguration.providerConfiguration = [:]
#if !os(tvOS)
            protocolConfiguration.excludeLocalNetworks = true
#endif
            return protocolConfiguration
        }()
        manager.isEnabled = onDemandEnabled
        manager.onDemandRules = [Self.connectOnDemandRule()]
        manager.isOnDemandEnabled = true

        do {
            try await performingOwnWrite { try await manager.saveToPreferences() }
        } catch {
            logger.error("Add: Saving configuration failed: \(error, privacy: .public)")
            manager.provider?.destroyStoredConfiguration()
            throw .addTunnelFailed(systemError: error)
        }

        if let existing {
            existing.refreshStatus()
            sortTunnels()
            return existing
        }

        let tunnel = TunnelContainer(tunnel: manager, clock: clock)
        insert(tunnel)
        return tunnel
    }

    func add(
        tunnelConfiguration: TunnelConfiguration,
        onDemandEnabled: Bool
    ) async throws(TunnelsServiceError) -> TunnelContainer {
        guard let name = tunnelConfiguration.name, !name.isEmpty else {
            throw .emptyName
        }
        guard !tunnels.contains(where: { $0.name == name }) else {
            throw .nameAlreadyExists
        }

        let manager = store.makeProfile()
        manager.set(tunnelConfiguration: tunnelConfiguration)
        manager.isEnabled = onDemandEnabled
        manager.onDemandRules = [Self.connectOnDemandRule()]
        manager.isOnDemandEnabled = true

        do {
            try await performingOwnWrite { try await manager.saveToPreferences() }
        } catch {
            logger.error("Add: Saving configuration failed: \(error, privacy: .public)")
            manager.provider?.destroyConfigurationReference()
            throw .addTunnelFailed(systemError: error)
        }

        let tunnel = TunnelContainer(tunnel: manager, clock: clock)
        insert(tunnel)
        return tunnel
    }

    func set(onDemandEnabled: Bool, for tunnel: TunnelContainer) async throws(TunnelsServiceError) {
        let manager = tunnel.tunnelProvider
        manager.isOnDemandEnabled = onDemandEnabled
        manager.isEnabled = onDemandEnabled

        do {
            try await performingOwnWrite { try await manager.saveToPreferences() }
        } catch {
            logger.error("Modify: Saving configuration failed: \(error, privacy: .public)")
            throw .addTunnelFailed(systemError: error)
        }

        defer { tunnel.refreshStatus() }
        do {
            try await manager.loadFromPreferences()
        } catch {
            logger.error("Modify: Re-loading after saving configuration failed: \(error, privacy: .public)")
            throw .loadTunnelsFailed(systemError: error)
        }
    }

    /// Saves a new configuration. If the tunnel is live and the configuration changed, the tunnel is
    /// stopped so the changes take effect; the method returns once it is `.disconnected` and the caller
    /// is expected to `startActivation(of:)` again.
    func modify(
        tunnel: TunnelContainer,
        isOnDemandEnabled: Bool,
        tunnelConfiguration: TunnelConfiguration
    ) async throws(TunnelsServiceError) {
        guard let name = tunnelConfiguration.name, !name.isEmpty else {
            throw .emptyName
        }

        let manager = tunnel.tunnelProvider
        manager.isOnDemandEnabled = isOnDemandEnabled
        manager.isEnabled = true

        let isNameChanged = name != (manager.localizedDescription ?? "")
        if isNameChanged {
            guard !tunnels.contains(where: { $0.name == name }) else {
                throw .nameAlreadyExists
            }
        }

        let isTunnelConfigurationChanged = manager.tunnelConfiguration != tunnelConfiguration
        if isTunnelConfigurationChanged {
            manager.set(tunnelConfiguration: tunnelConfiguration)
        }

        do {
            try await performingOwnWrite { try await manager.saveToPreferences() }
        } catch {
            logger.error("Modify: Saving configuration failed: \(error, privacy: .public)")
            throw .addTunnelFailed(systemError: error)
        }

        if isNameChanged {
            tunnel.rename(name)
            sortTunnels()
        }

        if isTunnelConfigurationChanged,
           [.connected, .connecting, .reasserting].contains(tunnel.status)
        {
            // Turn off the tunnel so the changes are made effective; the caller restarts it.
            await startDeactivation(of: tunnel)
        }

        defer { tunnel.refreshStatus() }
        do {
            try await manager.loadFromPreferences()
        } catch {
            logger.error("Modify: Re-loading after saving configuration failed: \(error, privacy: .public)")
            throw .loadTunnelsFailed(systemError: error)
        }
    }
}

// MARK: - Activation

extension TunnelsService {
    /// Starts the tunnel and suspends until it is `.connected`.
    /// Throws when the system reports `.disconnected` instead, or after `activationTimeout`.
    func startActivation(of tunnel: TunnelContainer) async throws(TunnelActivationError) {
        guard tunnels.contains(where: { $0 === tunnel }) else { throw .inactive }

        // Only one tunnel can be active at a time — wait for the others to go down first.
        for other in tunnels where other !== tunnel && other.status != .disconnected {
            logger.info("Tunnel '\(tunnel.name)' waiting for deactivation of '\(other.name)'")
            tunnel.status = .waiting
            await startDeactivation(of: other)
        }

        if tunnel.status == .connected { return }

        if [.disconnecting, .waiting].contains(tunnel.status) {
            _ = await tunnel.waitForStatus(in: [.disconnected, .connected], timeout: deactivationTimeout)
            tunnel.refreshStatus()
        }

        if tunnel.status == .disconnected {
            try await tunnel.startActivationAttempt()
        }

        guard tunnel.status != .connected else { return }

        switch await tunnel.waitForStatus(in: [.connected, .disconnected], timeout: activationTimeout) {
        case .connected:
            logger.debug("\(tunnel.name) is successfully activated")
        case .disconnected:
            throw .activationAttemptFailed(wasOnDemandEnabled: tunnel.tunnelProvider.isOnDemandEnabled)
        case nil, .some:
            logger.error("\(tunnel.name) did not reach .connected within \(self.activationTimeout)")
            tunnel.refreshStatus()
            throw .timedOut
        }
    }

    /// Stops the tunnel and suspends until it is `.disconnected` (bounded by `deactivationTimeout`).
    func startDeactivation(of tunnel: TunnelContainer) async {
        guard tunnel.status != .disconnected else { return }
        tunnel.requestDeactivation()
        _ = await tunnel.waitForStatus(in: [.disconnected], timeout: deactivationTimeout)
        tunnel.refreshStatus()
        logger.debug("\(tunnel.name) is deactivated (status: \(String(describing: tunnel.status)))")
    }

    /// Disables on-demand and stops the managed tunnel. Returns `false` when nothing was active.
    @discardableResult
    func startDeactivationOfActiveTunnel() async -> Bool {
        guard let tunnel = tunnels.last, tunnel.status != .disconnected else { return false }
        do {
            try await set(onDemandEnabled: false, for: tunnel)
        } catch {
            logger.error("Failed to disable on-demand before deactivation: \(error, privacy: .public)")
        }
        await startDeactivation(of: tunnel)
        return true
    }

    func refreshStatuses() {
        tunnels.forEach { $0.refreshStatus() }
        publishStatus()
    }
}

// MARK: - Removal

extension TunnelsService {
    func remove(tunnel: TunnelContainer) async throws(TunnelsServiceError) {
        let manager = tunnel.tunnelProvider
        manager.provider?.destroyStoredConfiguration()

        do {
            try await performingOwnWrite { try await manager.removeFromPreferences() }
        } catch {
            logger.error("Remove: Saving configuration failed: \(error, privacy: .public)")
            throw .removeTunnelFailed(systemError: error)
        }

        tunnels.removeAll { $0 === tunnel }
        publishStatus()
    }

    func removeMultiple(tunnels: [TunnelContainer]) async throws(TunnelsServiceError) {
        for tunnel in tunnels {
            try await remove(tunnel: tunnel)
        }
        await reload()
    }
}

// MARK: - Reloading

extension TunnelsService {
    /// Re-syncs `tunnels` with the system's list of configurations
    /// (tunnels added or removed outside the app).
    func reload() async {
        let loadedTunnelProviders: [any TunnelProfile]
        do {
            loadedTunnelProviders = try await store.loadAllProfiles()
        } catch {
            logger.error("Reload: failed to load tunnel managers: \(error, privacy: .public)")
            return
        }

        // Tunnels deleted outside the app
        tunnels.removeAll { current in
            !loadedTunnelProviders.contains { $0.isEquivalent(to: current) }
        }

        for loadedTunnelProvider in loadedTunnelProviders {
            if let matchingTunnel = tunnels.first(where: { loadedTunnelProvider.isEquivalent(to: $0) }) {
                matchingTunnel.tunnelProvider = loadedTunnelProvider
                matchingTunnel.refreshStatus()
            } else {
                // Tunnel added outside the app
                insert(TunnelContainer(tunnel: loadedTunnelProvider, clock: clock))
            }
        }
        publishStatus()
    }
}

// MARK: - Private

private extension TunnelsService {
    static func connectOnDemandRule() -> NEOnDemandRule {
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        return rule
    }

    func attach(_ tunnel: TunnelContainer) {
        tunnel.statusDidChange = { [weak self] _ in
            self?.publishStatus()
        }
    }

    func insert(_ tunnel: TunnelContainer) {
        attach(tunnel)
        tunnels.append(tunnel)
        sortTunnels()
        publishStatus()
    }

    func sortTunnels() {
        tunnels.sort { TunnelsService.nameIsLess(lhs: $0.name, than: $1.name) }
    }

    func publishStatus() {
        broadcaster.send(.status(tunnels.last?.status ?? .disconnected))
    }

    /// Runs one of our own preference writes and ignores the `NEVPNConfigurationChange`
    /// it produces, breaking the save → notify → reload feedback loop.
    func performingOwnWrite<T>(_ body: () async throws -> T) async throws -> T {
        defer { ignoreConfigurationChangesUntil = .now + .seconds(1) }
        return try await body()
    }

    func startObservingTunnelStatuses() {
        statusObservation = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .NEVPNStatusDidChange) {
                guard let self else { return }
                guard let session = notification.object as? NETunnelProviderSession,
                      let manager = session.manager as? NETunnelProviderManager
                else { continue }
                profileStatusDidChange(manager)
            }
        }
    }
}

// MARK: - Status changes

extension TunnelsService {
    /// A profile's connection status changed: the system's notification in the apps, the fake in tests. The session's
    /// manager is not always the service's own instance, so a profile with the same name and extension matches too:
    /// the apps name every engine's profile alike, and another app's profile can share the name.
    func profileStatusDidChange(_ profile: any TunnelProfile) {
        guard let tunnel = tunnels.first(where: {
            $0.tunnelProvider === profile || $0.tunnelProvider.isSameProfile(as: profile)
        })
        else { return }

        logger.debug("Tunnel '\(tunnel.name)' status changed to '\(profile.connectionStatus.description)'")
        tunnel.refreshStatus()
    }
}

private extension TunnelsService {
    func startObservingTunnelConfigurations() {
        configurationObservation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NEVPNConfigurationChange) {
                guard let self else { return }
                scheduleReloadIfNeeded()
            }
        }
    }

    func scheduleReloadIfNeeded() {
        guard ContinuousClock.now >= ignoreConfigurationChangesUntil else {
            logger.debug("Ignoring configuration change caused by our own write")
            return
        }
        // Debounce: the system can fire several notifications for one external change.
        pendingReload?.cancel()
        pendingReload = Task { [weak self, clock] in
            try? await clock.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }
}
