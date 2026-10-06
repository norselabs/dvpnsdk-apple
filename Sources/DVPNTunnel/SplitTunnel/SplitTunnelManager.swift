//
//  SplitTunnelManager.swift
//  DVPNCore
//

#if os(macOS)
import DVPNCoreKit
import DVPNSplitTunnelCore
import Foundation
import NetworkExtension

// MARK: - SplitTunnelError

public enum SplitTunnelError: LocalizedError, Sendable {
    /// The app declares no split-tunnel extension (`DVPNCoreConfiguration.splitTunnelProviderBundleID`).
    case notSupported
    case loadFailed(systemError: any Error)
    case saveFailed(systemError: any Error)
    case startFailed(systemError: any Error)

    public var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Split tunnelling is not available in this app"
        case let .loadFailed(error), let .saveFailed(error), let .startFailed(error):
            return error.localizedDescription
        }
    }
}

// MARK: - SplitTunnelManager

/// App-facing entry point of split tunnelling on macOS: the setting's home and the one
/// transparent-proxy configuration that applies it.
///
/// The proxy runs whenever the setting is enabled, VPN or no VPN, so an on-demand reconnect of the tunnel needs
/// nothing from the app; the extension itself leaves every flow alone while no tunnel is up. It does not start by
/// itself after a reboot or a quit: the app calls `startIfEnabled()` when it launches.
@MainActor
public final class SplitTunnelManager {
    private let configuration: DVPNCoreConfiguration
    private let store: any SplitTunnelProfileStore
    private let defaults: UserDefaults
    private let clock: any Clock<Duration>
    private var profile: (any SplitTunnelProfile)?

    public convenience init(configuration: DVPNCoreConfiguration) {
        self.init(configuration: configuration, store: SystemSplitTunnelProfileStore(), defaults: .shared, clock: ContinuousClock())
    }

    init(
        configuration: DVPNCoreConfiguration,
        store: any SplitTunnelProfileStore,
        defaults: UserDefaults,
        clock: any Clock<Duration>
    ) {
        self.configuration = configuration
        self.store = store
        self.defaults = defaults
        self.clock = clock
    }

    /// Whether this app has a split-tunnel extension at all.
    public var isSupported: Bool {
        configuration.splitTunnelProviderBundleID != nil
    }

    /// The saved setting.
    public func settings() -> SplitTunnelSettings {
        SplitTunnelSettingsStore.load(from: defaults)
    }

    /// Saves the setting and makes the proxy follow it when enabled: a running proxy is told to read it again, a
    /// stopped one is started; stopped when not. The first save of the proxy configuration shows the system's prompt;
    /// a declined prompt leaves the setting as it was.
    public func apply(_ settings: SplitTunnelSettings) async throws(SplitTunnelError) {
        guard isSupported else { throw .notSupported }
        let profile = settings.isEnabled ? try await prepareProfile() : nil
        do {
            try SplitTunnelSettingsStore.save(settings, in: defaults)
        } catch {
            throw .saveFailed(systemError: error)
        }
        if let profile {
            try await follow(profile)
        } else {
            await stop()
        }
    }

    /// Starts the proxy when the saved setting is enabled; for the app's launch. A proxy that is up, or coming up, is
    /// left alone: it runs with the saved setting, since `apply` restarts it for a new one. Restarting it at every
    /// launch crashed the extension in the system's flow start-up, right after the stop.
    public func startIfEnabled() async throws(SplitTunnelError) {
        guard isSupported, settings().isEnabled else { return }
        let profile = try await prepareProfile()
        guard ![.connected, .connecting, .reasserting].contains(profile.connectionStatus) else {
            logger.info("Split tunnel: proxy already running")
            return
        }
        try await start(profile)
    }

    /// Stops the proxy and keeps the setting: for a subscription that is no longer Plus, or the setting turned off.
    /// `startIfEnabled()` brings it back.
    public func stop() async {
        guard let profile = try? await loadProfile() else { return }
        profile.stopProxy()
        logger.info("Split tunnel: proxy stopped")
    }

    /// Whether the proxy is up.
    public func isRunning() async -> Bool {
        (try? await loadProfile())?.connectionStatus == .connected
    }
}

// MARK: - Private

private extension SplitTunnelManager {
    /// A running proxy reads a new setting from a message; a restart would do the same at the
    /// cost that crashed the extension, so it is only the fallback for a proxy that does not answer.
    func follow(_ profile: any SplitTunnelProfile) async throws(SplitTunnelError) {
        if profile.connectionStatus == .connected {
            do {
                _ = try await profile.sendMessage(SplitTunnelMessage.reloadSettings.data)
                logger.info("Split tunnel: the running proxy took the new setting")
                return
            } catch {
                logger.warning("Split tunnel: the running proxy did not take the new setting, restarting it: \(error.localizedDescription, privacy: .public)")
            }
        }
        try await start(profile)
    }

    func start(_ profile: any SplitTunnelProfile) async throws(SplitTunnelError) {
        if ![.disconnected, .invalid].contains(profile.connectionStatus) {
            // Running, or on its way: restart, so the extension reads the setting just saved.
            profile.stopProxy()
            _ = await wait(for: profile, toReach: .disconnected)
        }
        do {
            try profile.startProxy()
        } catch {
            logger.error("Split tunnel: starting the proxy failed: \(error, privacy: .public)")
            throw .startFailed(systemError: error)
        }
        if await wait(for: profile, toReach: .connected) {
            logger.info("Split tunnel: proxy started")
        } else {
            logger.warning("Split tunnel: the proxy did not report connected in time")
        }
    }

    /// The one proxy configuration for the app's extension: loaded, or created and saved, enabled and never
    /// on-demand. macOS keeps on-demand on one of an app's configurations at a time, and saving the proxy with it took
    /// it off the connected tunnel, whose on-demand keeps the VPN up across network changes.
    func prepareProfile() async throws(SplitTunnelError) -> any SplitTunnelProfile {
        guard let bundleID = configuration.splitTunnelProviderBundleID else { throw .notSupported }
        if let profile = try await loadProfile() {
            if !profile.isEnabled || profile.isOnDemandEnabled {
                profile.isEnabled = true
                profile.isOnDemandEnabled = false
                try await save(profile)
            }
            return profile
        }
        let profile = store.makeProfile()
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = bundleID
        protocolConfiguration.serverAddress = tunnelName
        profile.protocolConfiguration = protocolConfiguration
        profile.localizedDescription = tunnelName
        profile.isEnabled = true
        try await save(profile)
        self.profile = profile
        return profile
    }

    func save(_ profile: any SplitTunnelProfile) async throws(SplitTunnelError) {
        do {
            try await profile.saveToPreferences()
            try await profile.loadFromPreferences()
        } catch {
            logger.error("Split tunnel: saving the proxy configuration failed: \(error, privacy: .public)")
            throw .saveFailed(systemError: error)
        }
    }

    /// The app's proxy configuration, if one was saved before; ours by bundle ID, else whatever the app has.
    func loadProfile() async throws(SplitTunnelError) -> (any SplitTunnelProfile)? {
        if let profile { return profile }
        do {
            let all = try await store.loadAllProfiles()
            let bundleID = configuration.splitTunnelProviderBundleID
            profile = all.first { $0.providerBundleID == bundleID } ?? all.first
            return profile
        } catch {
            throw .loadFailed(systemError: error)
        }
    }

    /// The system's name for the configuration: the same as the VPN profile's.
    var tunnelName: String {
        configuration.protocols.first?.tunnelName ?? "VPN"
    }

    /// Polls the status for up to five seconds.
    func wait(for profile: any SplitTunnelProfile, toReach status: NEVPNStatus) async -> Bool {
        for _ in 0 ..< 25 {
            if profile.connectionStatus == status { return true }
            try? await clock.sleep(for: .milliseconds(200))
        }
        return profile.connectionStatus == status
    }
}
#endif
