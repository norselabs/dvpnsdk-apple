//
//  SplitTunnelProxyProvider.swift
//  DVPNCore
//

#if os(macOS)
import DVPNCoreKit
import DVPNSplitTunnelCore
import Network
import NetworkExtension
import notify
import os

// MARK: - SplitTunnelProxyProvider

/// Base transparent proxy for the macOS split-tunnel extension. The extension target only
/// subclasses it: `final class TransparentProxyProvider: SplitTunnelProxyProvider {}`
///
/// The packet tunnel keeps carrying everything. The system offers this proxy every outbound TCP and UDP flow with
/// its source app, except the system's DHCP and the local network's traffic (`SplitTunnelTraffic.excluded`). Flows
/// that belong in the VPN are declined (`false`) and proceed untouched; the flows of the apps that bypass the VPN are
/// copied through the proxy's own connections, bound to the physical interface, so they never enter the tunnel. DNS
/// is not offered (port 53 can only be matched by domain), so bypassing apps still resolve names through the tunnel's
/// resolver.
///
/// The proxy runs while split tunnelling is on (the app starts it at launch and whenever it sees the tunnel connect,
/// and it outlives the app), but it acts only while DVPN's tunnel is up, whoever started the tunnel: it offers itself
/// no flow otherwise.
///
/// `@unchecked`: every mutable property is behind a lock, and the rest never changes after `init`.
open class SplitTunnelProxyProvider: NETransparentProxyProvider, @unchecked Sendable {
    /// Handed to Network.framework for the relays' connections and the path monitor.
    private let queue = DispatchQueue(label: "io.norselabs.dvpn.split-tunnel")
    private let monitor = NWPathMonitor()
    private let relays = FlowRelays()
    private let settings = OSAllocatedUnfairLock(initialState: SplitTunnelSettings.disabled)
    /// Set when the system starts stopping the proxy: a flow offered from then on is declined, not relayed.
    private let isStopped = OSAllocatedUnfairLock(initialState: false)
    /// Set by the first start. The system can call `startProxy` twice for one start on macOS 26 and later
    /// (FB21464147); the second call must not start a second path monitor or set the rules again.
    private let hasStarted = OSAllocatedUnfairLock(initialState: false)
    /// Whether DVPN's tunnel is up: its provider says so (`TunnelStateStore`) and a tunnel interface is there, which a
    /// stale "up" after the tunnel crashed has not. Flows are offered only then.
    private let isTunnelUp = OSAllocatedUnfairLock(initialState: false)
    /// The rules to set, in order, for the one consumer that sets them.
    private let ruleChanges: AsyncStream<Bool>
    private let ruleChangesContinuation: AsyncStream<Bool>.Continuation
    private let notifyToken = OSAllocatedUnfairLock<Int32?>(initialState: nil)
    /// The app's bundle ID: the app's own flows and its extensions' never bypass, whatever the mode.
    private let ownAppID: String

    override public init() {
        // The extension's ID is the app's plus one component ("com.example.vpn.split-tunnel").
        ownAppID = (Bundle.main.bundleIdentifier ?? "").split(separator: ".").dropLast().joined(separator: ".")
        (ruleChanges, ruleChangesContinuation) = AsyncStream.makeStream(of: Bool.self)
        super.init()
    }

    override open nonisolated(nonsending) func startProxy(options: [String: Any]? = nil) async throws {
        let isFirstStart = hasStarted.withLock { started in
            defer { started = true }
            return !started
        }
        guard isFirstStart else {
            logger.warning("Split tunnel: a second start of the same proxy was ignored")
            return
        }
        let loaded = SplitTunnelSettingsStore.load()
        settings.withLock { $0 = loaded }
        // Nothing is offered until the path shows DVPN's tunnel up.
        try await setRules(offering: false)
        Task { [self] in
            for await offering in ruleChanges {
                try? await setRules(offering: offering)
            }
        }
        monitor.pathUpdateHandler = { [weak self] path in self?.follow(path) }
        monitor.start(queue: queue)
        var token: Int32 = 0
        notify_register_dispatch(TunnelStateStore.changeNotification, &token, queue) { [weak self] _ in
            guard let self else { return }
            follow(monitor.currentPath)
        }
        let registered = token
        notifyToken.withLock { $0 = registered }
        logger.info("Split tunnel started: \(loaded.mode.rawValue, privacy: .public), \(loaded.apps.count) app(s)")
    }

    override open nonisolated(nonsending) func stopProxy(with reason: NEProviderStopReason) async {
        isStopped.withLock { $0 = true }
        if let token = notifyToken.withLock({ $0 }) { notify_cancel(token) }
        ruleChangesContinuation.finish()
        monitor.cancel()
        relays.cancelAll()
        logger.info("Split tunnel stopped: \(reason.rawValue, privacy: .public)")
    }

    /// The app's messages (`SplitTunnelMessage`): a setting change is read again here instead of restarting the proxy,
    /// whose restarts crashed the extension.
    override open nonisolated(nonsending) func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let message = SplitTunnelMessage(data: messageData) else { return nil }
        switch message {
        case .reloadSettings:
            let loaded = SplitTunnelSettingsStore.load()
            settings.withLock { $0 = loaded }
            logger.info("Split tunnel settings reloaded: \(loaded.mode.rawValue, privacy: .public), \(loaded.apps.count) app(s)")
            return message.data
        }
    }

    /// A declined flow (`false`) goes on as if there were no proxy; the proxy never closes it.
    override open func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // While DVPN's tunnel is down no flow should be offered; one offered while the rules change is declined.
        guard !isStopped.withLock({ $0 }), isTunnelUp.withLock({ $0 }) else { return false }
        let app = flow.metaData.sourceAppSigningIdentifier
        let bypasses = !isOwn(app) && settings.withLock { $0.bypassesVPN(app) }
        logger.debug("Flow from '\(app, privacy: .public)' \(bypasses ? "bypasses the VPN" : "stays in the VPN", privacy: .public)")
        guard bypasses else { return false }
        guard let interface = physicalInterface else {
            logger.warning("No physical interface for \(app, privacy: .public): the flow stays in the VPN")
            return false
        }
        relays.relay(flow, via: interface, on: queue)
        return true
    }
}

// MARK: - Private

private extension SplitTunnelProxyProvider {
    func isOwn(_ app: String) -> Bool {
        !ownAppID.isEmpty && (app == ownAppID || app.hasPrefix(ownAppID + "."))
    }

    /// The interface the tunnel itself uses: the first one that is neither a tunnel (`.other`, as utun reports)
    /// nor loopback.
    var physicalInterface: NWInterface? {
        monitor.currentPath.availableInterfaces.first { $0.type != .other && $0.type != .loopback }
    }

    /// Re-reads whether DVPN's tunnel is up, on a path change or the tunnel's notification, and has the rules follow.
    func follow(_ path: NWPath) {
        guard !isStopped.withLock({ $0 }) else { return }
        let isUp = TunnelStateStore.isUp() && path.availableInterfaces.contains { $0.type == .other }
        let changed = isTunnelUp.withLock { current in
            defer { current = isUp }
            return current != isUp
        }
        guard changed else { return }
        logger.info("Split tunnel: DVPN's tunnel is \(isUp ? "up, flows are offered" : "down, no flow is offered", privacy: .public)")
        ruleChangesContinuation.yield(isUp)
    }

    /// Offers every flow but the excluded ones, or none. A system that refused an empty rule list gets every flow,
    /// which `handleNewFlow` then declines while the tunnel is down.
    func setRules(offering: Bool) async throws {
        let network = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        network.includedNetworkRules = offering ? SplitTunnelTraffic.offered.map(Self.rule) : []
        network.excludedNetworkRules = SplitTunnelTraffic.excluded.map(Self.rule)
        do {
            try await setTunnelNetworkSettings(network)
        } catch where !offering {
            logger.error("Split tunnel: no rules were refused (\(error.localizedDescription, privacy: .public)); offering every flow")
            try await setRules(offering: true)
        }
    }

    static func rule(for destination: SplitTunnelTraffic.Destination) -> NENetworkRule {
        let port = destination.port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        return NENetworkRule(
            destinationNetworkEndpoint: .hostPort(host: NWEndpoint.Host(destination.address), port: port),
            prefix: destination.prefix,
            protocol: destination.isUDPOnly ? .UDP : .any
        )
    }
}
#endif
