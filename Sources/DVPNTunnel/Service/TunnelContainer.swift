//
//  TunnelContainer.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNSDK
import Foundation
import NetworkExtension
import WireGuardKit

// MARK: - Constants

private struct Constants {
    let maxActivationAttempts = 8
}

private let constants = Constants()

// MARK: - TunnelContainer

@MainActor
final class TunnelContainer {
    private(set) var name: String
    private(set) var isActivateOnDemandEnabled: Bool
    var tunnelProvider: any TunnelProfile

    var status: TunnelStatus {
        didSet {
            guard oldValue != status else { return }
            statusDidChange?(self)
            resolveWaiters(for: status)
        }
    }

    private(set) var activationAttemptId: String?

    /// Set by `TunnelsService` to be notified about status transitions.
    var statusDidChange: ((TunnelContainer) -> Void)?

    private struct Waiter {
        let terminal: Set<TunnelStatus>
        let continuation: CheckedContinuation<TunnelStatus?, Never>
        let timeout: Task<Void, Never>
    }

    private var waiters: [UUID: Waiter] = [:]
    private let clock: any Clock<Duration>

    /// `clock` drives the status-wait timeouts and the handshake poll; tests pass an immediate clock.
    init(tunnel: any TunnelProfile, clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
        name = tunnel.localizedDescription ?? "Unnamed"
        status = TunnelStatus(from: tunnel.connectionStatus)
        isActivateOnDemandEnabled = tunnel.isOnDemandEnabled
        tunnelProvider = tunnel
    }
}

// MARK: - Computed properties

extension TunnelContainer {
    var tunnelConfiguration: TunnelConfiguration? {
        tunnelProvider.tunnelConfiguration
    }

    /// The protocol descriptor matching the provider's bundle identifier, if the app declares it.
    var descriptor: TunnelProtocolDescriptor? {
        TunnelEnvironment.requiredConfiguration
            .descriptor(forProviderBundleID: tunnelProvider.provider?.providerBundleIdentifier)
    }

    var sessionStatus: NEVPNStatus {
        tunnelProvider.connectionStatus
    }
}

// MARK: - Public methods

extension TunnelContainer {
    /// Re-reads name, status and on-demand flag from the underlying provider.
    func refreshStatus() {
        name = tunnelProvider.localizedDescription ?? name
        isActivateOnDemandEnabled = tunnelProvider.isOnDemandEnabled
        status = TunnelStatus(from: tunnelProvider.connectionStatus)
    }

    /// Suspends until the connected tunnel can actually carry traffic.
    ///
    /// `.connected` only means the provider started: WireGuard-family engines still have to
    /// complete their first handshake before packets flow. This polls the provider's runtime
    /// configuration for `last_handshake_time_sec`. Proxy engines (Xray, Hysteria) are ready as
    /// soon as they are connected. Returns `false` if the tunnel is not connected or `timeout` elapses.
    func waitUntilReady(timeout: Duration) async -> Bool {
        if case .completed = await readiness(timeout: timeout) { return true }
        return false
    }

    /// Outcome of waiting for the tunnel to carry traffic.
    enum Readiness: Sendable, Equatable {
        /// Ready (proxy engines immediately; WireGuard after the first handshake).
        case completed
        /// The runtime configuration was readable and reported no handshake before `timeout`.
        case timedOut
        /// The tunnel is not connected, or the extension never answered the runtime-configuration
        /// request, so the handshake cannot be observed at all (`reason` says why).
        case unavailable(reason: String)
    }

    /// Like `waitUntilReady`, but tells "no handshake" apart from "cannot observe the handshake".
    func readiness(timeout: Duration) async -> Readiness {
        guard status == .connected else { return .unavailable(reason: "tunnel status is \(status)") }
        switch descriptor?.readiness ?? .wireGuardHandshake {
        case .immediate:
            return .completed
        case .wireGuardHandshake:
            return await waitForWireGuardHandshake(timeout: timeout)
        }
    }

    /// Suspends until `status` becomes one of `terminal`, or `timeout` elapses (returns `nil`).
    func waitForStatus(in terminal: Set<TunnelStatus>, timeout: Duration) async -> TunnelStatus? {
        if terminal.contains(status) { return status }

        let id = UUID()
        return await withCheckedContinuation { continuation in
            let timeoutTask = Task { [weak self, clock] in
                try? await clock.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.resolve(waiter: id, with: nil)
            }
            waiters[id] = Waiter(terminal: terminal, continuation: continuation, timeout: timeoutTask)
        }
    }
}

// MARK: - Internal methods

extension TunnelContainer {
    func rename(_ newName: String) {
        name = newName
    }

    /// Asks the system to start the tunnel. Returns once `startTunnel(options:)` has been accepted;
    /// the actual `.connected` transition arrives through `status`.
    /// Re-enables a disabled provider and reloads a stale configuration, up to 8 attempts
    func startActivationAttempt() async throws(TunnelActivationError) {
        logger.debug("Starting activation attempt (tunnel: \(self.name, privacy: .public))")
        var lastError: Error?

        for _ in 0 ..< constants.maxActivationAttempts {
            // Ensure that no other tunnel can attempt activation until this tunnel is done trying
            status = .connecting

            guard tunnelProvider.isEnabled else {
                logger.debug("Tunnel is disabled. Re-enabling and saving")
                tunnelProvider.isEnabled = true
                do {
                    try await tunnelProvider.saveToPreferences()
                } catch {
                    logger.error("Error saving tunnel after re-enabling: \(error, privacy: .public)")
                    status = .disconnected
                    throw .savingFailed(systemError: error)
                }
                lastError = NEVPNError(.configurationUnknown)
                continue
            }

            let attemptID = UUID().uuidString
            activationAttemptId = attemptID

            do {
                try tunnelProvider.startTunnel(activationAttemptID: attemptID)
                logger.debug("startActivation: Success")
                return
            } catch let error as NEVPNError
                where error.code == .configurationInvalid || error.code == .configurationStale
            {
                logger.debug("Configuration is stale or invalid. Reloading tunnel and retrying.")
                do {
                    try await tunnelProvider.loadFromPreferences()
                } catch {
                    logger.error("startActivation: Error reloading tunnel: \(error, privacy: .public)")
                    status = .disconnected
                    throw .loadingFailed(systemError: error)
                }
                lastError = error
            } catch {
                logger.error("Failed to activate tunnel: \(error, privacy: .public)")
                status = .disconnected
                throw .startingFailed(systemError: error)
            }
        }

        logger.error("Failed after \(constants.maxActivationAttempts) attempts. Giving up.")
        status = .disconnected
        throw .retryLimitReached(lastSystemError: lastError ?? NEVPNError(.configurationUnknown))
    }

    /// Asks the system to stop the tunnel. `.disconnected` arrives through `status`.
    func requestDeactivation() {
        logger.debug("requestDeactivation: Tunnel: \(self.name, privacy: .public)")
        switch sessionStatus {
        case .disconnected, .invalid:
            status = .disconnected
        default:
            tunnelProvider.stopTunnel()
            status = .disconnecting
        }
    }
}

// MARK: - Private methods

private extension TunnelContainer {
    func waitForWireGuardHandshake(timeout: Duration) async -> Readiness {
        let hasTimeLeft = clock.timeLeft(for: timeout)
        var observedPending = false
        var lastReason = "never asked"
        while hasTimeLeft() {
            switch await probeHandshake() {
            case .completed:
                return .completed
            case .pending:
                observedPending = true
            case let .unavailable(reason):
                if reason != lastReason {
                    logger.info("Handshake not observable for '\(self.name, privacy: .public)': \(reason, privacy: .public)")
                }
                lastReason = reason
            }
            try? await clock.sleep(for: .milliseconds(500))
            guard status == .connected else { return .unavailable(reason: "tunnel status is \(status)") }
        }
        if observedPending {
            logger.warning("WireGuard handshake not observed within \(timeout) for '\(self.name, privacy: .public)'")
            return .timedOut
        }
        logger.warning("WireGuard handshake unobservable for '\(self.name, privacy: .public)': \(lastReason, privacy: .public)")
        return .unavailable(reason: lastReason)
    }

    /// Asks the WireGuard provider for its runtime configuration (`handleAppMessage` with `[0]`)
    /// and reads the peer's handshake state from it.
    func probeHandshake() async -> HandshakeProbe {
        guard tunnelProvider.hasProviderSession else { return .unavailable("no provider session") }
        let response: Data?
        do {
            response = try await tunnelProvider.sendProviderMessage(Data([0]))
        } catch {
            return .unavailable("provider message failed: \(error.localizedDescription)")
        }
        guard let data = response, !data.isEmpty else { return .unavailable("extension returned no runtime configuration") }
        guard let configuration = String(data: data, encoding: .utf8) else { return .unavailable("runtime configuration is not UTF-8") }
        return Self.handshakeProbe(runtimeConfiguration: configuration)
    }

    func resolveWaiters(for status: TunnelStatus) {
        for (id, waiter) in waiters where waiter.terminal.contains(status) {
            resolve(waiter: id, with: status)
        }
    }

    func resolve(waiter id: UUID, with status: TunnelStatus?) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        waiter.continuation.resume(returning: status)
    }
}

// MARK: - Handshake probe

extension TunnelContainer {
    enum HandshakeProbe: Equatable {
        case completed
        case pending
        case unavailable(String)
    }

    /// Reads the peer's handshake state from UAPI `get=1` text. `rx_bytes > 0` counts as a handshake
    /// too: data can only be decrypted after one.
    nonisolated static func handshakeProbe(runtimeConfiguration: String) -> HandshakeProbe {
        var sawPeer = false
        for line in runtimeConfiguration.split(separator: "\n") {
            for key in ["last_handshake_time_sec=", "rx_bytes="] where line.hasPrefix(key) {
                sawPeer = true
                if (Int(line.dropFirst(key.count)) ?? 0) > 0 { return .completed }
            }
        }
        return sawPeer ? .pending : .unavailable("runtime configuration lists no peer (\(runtimeConfiguration.count) bytes)")
    }
}

// MARK: - Clock

private extension Clock where Duration == Swift.Duration {
    /// Measures `timeout` on this clock, the one the handshake polls sleep on: a test's immediate clock then
    /// ends the wait at once instead of spinning until the wall clock's deadline.
    func timeLeft(for timeout: Duration) -> () -> Bool {
        let deadline = now.advanced(by: timeout)
        return { now < deadline }
    }
}
