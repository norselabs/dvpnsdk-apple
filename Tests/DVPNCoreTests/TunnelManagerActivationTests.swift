//
//  TunnelManagerActivationTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing

/// What `TunnelManager` does when a start fails: on-demand goes off and the attempt stops,
/// a proxy engine's recorded reason reaches the error, and a WireGuard tunnel without a first handshake
/// is stopped. A stop that follows a failure is announced to the provider first, so the provider writes its log
/// file (`ExtensionLogFile`); a stop the app asks for otherwise is not.
///
/// Every proxy start clears the shared `ProxyStartErrorStore`, and every start past its checks writes the shared
/// `NodeAddressStore` (App Group defaults), so the suite runs serially.
@MainActor
@Suite(.serialized)
struct TunnelManagerActivationTests {
    private let configuration = DVPNCoreConfiguration(
        appGroupID: "group.com.example.vpn.tests",
        protocols: [
            TunnelProtocolDescriptor(
                id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
            ),
            TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
        ]
    )

    init() {
        DVPNCore.bootstrap(configuration)
    }

    @Test
    func aFailedStartTurnsOnDemandOffAndStopsTheAttempt() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: "com.example.vpn.v2ray-ne")
        profile.isOnDemandEnabled = true
        profile.startOutcomes = [.fail]
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await manager.activate(tunnel, in: service)
        } throws: { error in
            if case .activationFailed = error as? TunnelsServiceError { return true }
            return false
        }
        #expect(!profile.isOnDemandEnabled)
        #expect(tunnel.status == .disconnected)
        #expect(!profile.messages.contains(ExtensionLogFile.failedStopNotice), "the tunnel is down")
    }

    /// A start still connecting when its time runs out is stopped as a failure, announced first.
    @Test
    func aStartThatTimesOutAnnouncesItsStop() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: "com.example.vpn.v2ray-ne")
        profile.startOutcomes = [.stayConnecting]
        var announcedBeforeTheStop = false
        profile.onStop = { [unowned profile] in
            announcedBeforeTheStop = profile.messages.contains(ExtensionLogFile.failedStopNotice)
        }
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await manager.activate(tunnel, in: service)
        } throws: { error in
            if case .activationFailed = error as? TunnelsServiceError { return true }
            return false
        }
        #expect(announcedBeforeTheStop)
        #expect(profile.stops == 1)
    }

    /// A save the system refuses after a failed start is tried once more, and the failure still reaches the caller.
    @Test
    func aRefusedOnDemandOffIsTriedOnceMore() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: "com.example.vpn.v2ray-ne")
        profile.isOnDemandEnabled = true
        profile.startOutcomes = [.fail]
        struct Refused: Error {}
        profile.onStart = { profile.saveError = Refused() }
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)
        let savesBefore = profile.saves

        await #expect {
            try await manager.activate(tunnel, in: service)
        } throws: { error in
            if case .activationFailed = error as? TunnelsServiceError { return true }
            return false
        }
        // Two attempts to turn on-demand off; this path saved nothing before the start.
        #expect(profile.saves == savesBefore + 2)
        #expect(tunnel.status == .disconnected)
    }

    @Test
    func aProxyEnginesRecordedReasonReachesTheError() async throws {
        defer { ProxyStartErrorStore.clear() }
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: "com.example.vpn.v2ray-ne")
        profile.startOutcomes = [.fail]
        profile.onStart = { ProxyStartErrorStore.record("no valid outbound found") }
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await manager.activate(tunnel, in: service)
        } throws: { error in
            (error as? TunnelsServiceError).map { "\($0)".contains("no valid outbound found") } == true
        }
    }

    @Test
    func aWireGuardTunnelWithoutAHandshakeIsStopped() async throws {
        let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
        profile.isOnDemandEnabled = true
        profile.messageAnswer = Data("public_key=abc\nlast_handshake_time_sec=0\nrx_bytes=0\n".utf8)
        var announcedBeforeTheStop = false
        profile.onStop = { [unowned profile] in
            announcedBeforeTheStop = profile.messages.contains(ExtensionLogFile.failedStopNotice)
        }
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await manager.activate(tunnel, in: service)
        } throws: { error in
            if case .activationFailed(.handshakeTimedOut) = error as? TunnelsServiceError { return true }
            return false
        }
        #expect(!profile.isOnDemandEnabled)
        #expect(profile.stops == 1)
        #expect(tunnel.status == .disconnected)
        #expect(announcedBeforeTheStop, "the provider takes the stop for the user's unless told")
    }

    /// A provider that never answers the announcement does not hold the stop up: the stop goes ahead after
    /// `TunnelManager.failedStopNoticeTimeout`.
    @Test(.timeLimit(.minutes(1)))
    func aProviderThatNeverAnswersIsStoppedAnyway() async throws {
        let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
        profile.messageAnswer = Data("public_key=abc\nlast_handshake_time_sec=0\nrx_bytes=0\n".utf8)
        profile.unansweredMessages = [ExtensionLogFile.failedStopNotice]
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await manager.activate(tunnel, in: service)
        } throws: { error in
            if case .activationFailed(.handshakeTimedOut) = error as? TunnelsServiceError { return true }
            return false
        }
        #expect(profile.messages.contains(ExtensionLogFile.failedStopNotice))
        #expect(profile.stops == 1)
        #expect(tunnel.status == .disconnected)
    }

    @Test
    func aWireGuardTunnelWithAHandshakeStaysUp() async throws {
        let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
        profile.messageAnswer = Data("public_key=abc\nlast_handshake_time_sec=1790000000\n".utf8)
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)

        try await manager.activate(tunnel, in: service)

        #expect(tunnel.status == .connected)
        #expect(profile.stops == 0)
    }

    /// A stop the app asks for when nothing failed is not announced: the provider writes no log file, which an
    /// ordinary disconnect would wait for.
    @Test
    func aPlannedStopAnnouncesNothing() async throws {
        let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
        profile.messageAnswer = Data("public_key=abc\nlast_handshake_time_sec=1790000000\n".utf8)
        let (manager, service) = makeManager([profile])
        let tunnel = try #require(service.tunnels.first)
        try await manager.activate(tunnel, in: service)

        try await manager.stop()

        #expect(profile.stops == 1)
        #expect(!profile.messages.contains(ExtensionLogFile.failedStopNotice))
    }

    /// Credentials without a WireGuard key fail before any profile is touched, for AmneziaWG as for WireGuard.
    @Test(arguments: [NodeType.wireguard, .amneziawg])
    func aStartWithoutAKeyFails(nodeType: NodeType) async throws {
        let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
        let (manager, _) = makeManager([profile])
        let node = WireGuardEndpoint(
            host: "203.0.113.10", port: 51820, clientAddress: "10.10.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
        )
        let endpoint: ConnectionEndpoint = nodeType == .wireguard
            ? .wireGuard(node)
            : .amneziaWG(AmneziaWGEndpoint(wireGuard: node, parameters: [:]))

        await #expect(throws: TunnelsServiceError.emptyCredentials) {
            try await manager.start(from: ConnectionCredentials(nodeType: nodeType, endpoint: endpoint))
        }
        #expect(profile.saves == 0)
        #expect(profile.starts == 0)
    }

    /// A start stores its node's address for the extension's start line once it is past its checks, and one without an
    /// address forgets the previous; a start that fails before then leaves the address of the configuration a restart
    /// runs.
    @Test
    func aStartStoresItsNodesAddress() async throws {
        struct Refused: Error {}
        try await withConfigurationFilesOfItsOwn {
            let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
            // A start past its checks then fails at the save.
            profile.saveError = Refused()
            let (manager, _) = makeManager([profile])
            let endpoint = ConnectionEndpoint.wireGuard(WireGuardEndpoint(
                host: "203.0.113.10", port: 51820, clientAddress: "10.10.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
            ))
            let server = Server(
                id: "srv-1", countryID: "DE", cityID: "c-1", name: "Berlin 1", isAvailable: true, serverProtocol: "WIREGUARD",
                address: "sentnode1qx7example"
            )
            let key = "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U="
            NodeAddressStore.record("sentnode1qx7previous")
            defer { NodeAddressStore.record(nil) }

            // Without a key, the start fails at its checks.
            await #expect(throws: TunnelsServiceError.emptyCredentials) {
                try await manager.start(from: ConnectionCredentials(nodeType: .wireguard, endpoint: endpoint, server: server))
            }
            #expect(NodeAddressStore.load() == "sentnode1qx7previous")

            await #expect(throws: TunnelsServiceError.self) {
                try await manager.start(from: ConnectionCredentials(nodeType: .wireguard, endpoint: endpoint, privateKey: key, server: server))
            }
            #expect(NodeAddressStore.load() == "sentnode1qx7example")

            await #expect(throws: TunnelsServiceError.self) {
                try await manager.start(from: ConnectionCredentials(nodeType: .wireguard, endpoint: endpoint, privateKey: key))
            }
            #expect(NodeAddressStore.load() == nil)
        }
    }

    /// The proxy starts store it at the same point: a V2Ray start without a UUID, and a Hysteria start in an app that
    /// declares no Hysteria extension, fail at their checks and leave it; a V2Ray start past them replaces it.
    @Test
    func aProxyStartStoresItsNodesAddressOncePastItsChecks() async throws {
        struct Refused: Error {}
        try await withConfigurationFilesOfItsOwn {
            let profile = FakeTunnelProfile(name: "Xray", providerBundleID: "com.example.vpn.v2ray-ne")
            // A start past its checks then fails at the save.
            profile.saveError = Refused()
            let (manager, _) = makeManager([profile])
            let node = ConnectionEndpoint.v2ray(V2RayNodeEndpoint(
                host: "203.0.113.20", inbounds: [V2RayInbound(port: 8443, proxyProtocol: .vmess, transport: .grpc)]
            ))
            let server = Server(
                id: "srv-2", countryID: "DE", cityID: "c-1", name: "Berlin 2", isAvailable: true, serverProtocol: "V2RAY",
                address: "sentnode1qx7example"
            )
            let uid = "11111111-2222-3333-4444-555555555555"
            NodeAddressStore.record("sentnode1qx7previous")
            defer { NodeAddressStore.record(nil) }

            await #expect(throws: TunnelsServiceError.emptyCredentials) {
                try await manager.start(from: ConnectionCredentials(nodeType: .v2ray, endpoint: node, server: server))
            }
            #expect(NodeAddressStore.load() == "sentnode1qx7previous")

            await #expect(throws: TunnelsServiceError.unsupportedProtocol) {
                try await manager.start(from: ConnectionCredentials(
                    nodeType: .hysteria, endpoint: .hysteria(HysteriaEndpoint(host: "203.0.113.30", port: 443)), uid: uid,
                    server: server
                ))
            }
            #expect(NodeAddressStore.load() == "sentnode1qx7previous")

            await #expect(throws: TunnelsServiceError.self) {
                try await manager.start(from: ConnectionCredentials(nodeType: .v2ray, endpoint: node, uid: uid, server: server))
            }
            #expect(NodeAddressStore.load() == "sentnode1qx7example")
            #expect(profile.saves == 1, "past its checks, it reached the profile's save")
        }
    }

    /// Runs `body` with the configuration files in a directory of their own, removed afterwards: a test process cannot
    /// write the App Group container.
    private func withConfigurationFilesOfItsOwn(_ body: () async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await TunnelConfigDirectories.$homeDirectoryOverride.withValue(directory) {
            try await body()
        }
    }

    /// A manager over a service of fake profiles that report their status changes to it.
    private func makeManager(_ profiles: [FakeTunnelProfile]) -> (TunnelManager, TunnelsService) {
        let store = FakeTunnelProfileStore()
        store.profiles = profiles
        let service = TunnelsService(tunnelProviders: profiles, store: store, clock: StepClock())
        profiles.forEach { $0.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) } }
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: configuration)
        manager.attach(service)
        return (manager, service)
    }
}
