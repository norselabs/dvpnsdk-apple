//
//  TunnelManagerActivationTests.swift
//  DVPNCore
//

import DVPNCoreKit
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing

/// What `TunnelManager` does when a start fails: on-demand goes off and the attempt stops,
/// a proxy engine's recorded reason reaches the error, and a WireGuard tunnel without a first handshake
/// is stopped.
///
/// Every proxy start clears the shared `ProxyStartErrorStore` (App Group defaults), so the suite runs serially.
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
            (error as? TunnelsServiceError)?.errorDescription?.contains("no valid outbound found") == true
        }
    }

    @Test
    func aWireGuardTunnelWithoutAHandshakeIsStopped() async throws {
        let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
        profile.isOnDemandEnabled = true
        profile.messageAnswer = Data("public_key=abc\nlast_handshake_time_sec=0\nrx_bytes=0\n".utf8)
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
