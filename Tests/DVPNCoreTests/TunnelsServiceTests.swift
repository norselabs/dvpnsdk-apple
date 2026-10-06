//
//  TunnelsServiceTests.swift
//  DVPNCore
//

import DVPNCoreKit
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing

/// The tunnel service against fake profiles: one profile for every engine, activation and its
/// failures, stopping, and profiles changed outside the app. `StepClock` makes every timeout elapse at once.
@MainActor
struct TunnelsServiceTests {
    private let xray = TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate)
    private let hysteria = TunnelProtocolDescriptor(
        id: .hysteria, providerBundleID: "com.example.vpn.hysteria-ne", tunnelName: "Hysteria", readiness: .immediate
    )

    init() {
        DVPNCore.bootstrap(
            DVPNCoreConfiguration(
                appGroupID: "group.com.example.vpn.tests",
                protocols: [
                    TunnelProtocolDescriptor(
                        id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
                    ),
                    TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
                ]
            )
        )
    }

    // MARK: Profiles

    @Test
    func aProxyStartCreatesOneProfileWithOnDemand() async throws {
        let (service, store) = makeService()

        let tunnel = try await service.startProxyTunnel(xray, onDemandEnabled: true)

        let profile = try #require(store.made.first)
        #expect(store.made.count == 1)
        #expect(profile.saves == 1)
        #expect(profile.localizedDescription == "Xray")
        #expect(profile.provider?.providerBundleIdentifier == "com.example.vpn.v2ray-ne")
        #expect(profile.isEnabled && profile.isOnDemandEnabled)
        #expect(profile.onDemandRules?.count == 1)
        #expect(service.tunnels.count == 1 && service.tunnels.first === tunnel)
    }

    /// Every engine rewrites the one profile; none creates a second.
    @Test
    func anotherEngineRewritesTheSameProfile() async throws {
        let existing = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        let (service, store) = makeService([existing])

        _ = try await service.startProxyTunnel(hysteria, onDemandEnabled: true)

        #expect(store.made.isEmpty)
        #expect(service.tunnels.count == 1)
        #expect(existing.localizedDescription == "Hysteria")
        #expect(existing.provider?.providerBundleIdentifier == "com.example.vpn.hysteria-ne")
    }

    @Test
    func aProfileTheSystemRefusesToSaveIsNotKept() async throws {
        let (service, store) = makeService()
        store.onMake = { $0.saveError = NSError(domain: NEVPNErrorDomain, code: NEVPNError.Code.configurationReadWriteFailed.rawValue) }

        await #expect {
            _ = try await service.startProxyTunnel(xray, onDemandEnabled: true)
        } throws: { error in
            (error as? TunnelsServiceError)?.isPermissionDenied == true
        }
        #expect(service.tunnels.isEmpty)
    }

    // MARK: Activation

    @Test
    func activationReturnsOnceTheProviderConnects() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        try await service.startActivation(of: tunnel)

        #expect(tunnel.status == .connected)
        #expect(profile.starts == 1)
    }

    @Test
    func aProviderThatStopsFailsTheActivation() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        profile.startOutcomes = [.fail]
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await service.startActivation(of: tunnel)
        } throws: { error in
            if case .activationAttemptFailed = error as? TunnelActivationError { return true }
            return false
        }
        #expect(tunnel.status == .disconnected)
    }

    @Test
    func aProviderThatNeverConnectsTimesOut() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        profile.startOutcomes = [.stayConnecting]
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await service.startActivation(of: tunnel)
        } throws: { error in
            if case .timedOut = error as? TunnelActivationError { return true }
            return false
        }
    }

    @Test
    func aStaleConfigurationIsReloadedAndTriedAgain() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        profile.startOutcomes = [.throwing(NEVPNError(.configurationStale)), .connect]
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        try await service.startActivation(of: tunnel)

        #expect(profile.loads == 1)
        #expect(profile.starts == 2)
        #expect(tunnel.status == .connected)
    }

    @Test
    func aConfigurationThatStaysStaleGivesUpAfterEightAttempts() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        profile.startOutcomes = [.throwing(NEVPNError(.configurationStale))]
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        await #expect {
            try await service.startActivation(of: tunnel)
        } throws: { error in
            if case .retryLimitReached = error as? TunnelActivationError { return true }
            return false
        }
        #expect(profile.starts == 8)
        #expect(tunnel.status == .disconnected)
    }

    @Test
    func aDisabledProfileIsEnabledAndSavedBeforeItStarts() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        profile.isEnabled = false
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        try await service.startActivation(of: tunnel)

        #expect(profile.isEnabled)
        #expect(profile.saves == 1)
        #expect(profile.starts == 1)
    }

    // MARK: Stopping

    @Test
    func stoppingTheTunnelTurnsOnDemandOffFirst() async throws {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID, status: .connected)
        profile.isOnDemandEnabled = true
        let (service, _) = makeService([profile])
        let tunnel = try #require(service.tunnels.first)

        #expect(await service.startDeactivationOfActiveTunnel())

        #expect(!profile.isOnDemandEnabled)
        #expect(profile.saves == 1)
        #expect(profile.stops == 1)
        #expect(tunnel.status == .disconnected)
    }

    @Test
    func withNothingConnectedStoppingDoesNothing() async {
        let profile = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        let (service, _) = makeService([profile])

        #expect(await service.startDeactivationOfActiveTunnel() == false)
        #expect(profile.stops == 0)
        #expect(profile.saves == 0)
    }

    // MARK: Outside changes

    @Test
    func aReloadPicksUpProfilesAddedAndRemovedOutsideTheApp() async {
        let old = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        let (service, store) = makeService([old])
        let added = FakeTunnelProfile(name: "Hysteria", providerBundleID: hysteria.providerBundleID)
        store.profiles = [added]

        await service.reload()

        #expect(service.tunnels.count == 1)
        #expect(service.tunnels.first?.tunnelProvider === added)
    }

    @Test
    func anotherProfilesStatusChangeIsIgnored() throws {
        let ours = FakeTunnelProfile(name: "Xray", providerBundleID: xray.providerBundleID)
        let (service, _) = makeService([ours])
        let tunnel = try #require(service.tunnels.first)
        let theirs = FakeTunnelProfile(name: "Another VPN", status: .connected)

        service.profileStatusDidChange(theirs)

        #expect(tunnel.status == .disconnected)
    }

    /// The system hands the notification's manager as its own instance: the same name and extension identify ours.
    @Test
    func theSystemsInstanceOfOurProfileMatchesByNameAndExtension() throws {
        let ours = FakeTunnelProfile(name: "DVPN", providerBundleID: xray.providerBundleID)
        let (service, _) = makeService([ours])
        let tunnel = try #require(service.tunnels.first)
        let systemsInstance = FakeTunnelProfile(name: "DVPN", providerBundleID: xray.providerBundleID, status: .connected)
        ours.connectionStatus = .connected

        service.profileStatusDidChange(systemsInstance)

        #expect(tunnel.status == .connected)
    }

    /// Another app's profile with the same name does not match: the extension tells them apart.
    @Test
    func anotherAppsProfileWithTheSameNameIsIgnored() throws {
        let ours = FakeTunnelProfile(name: "DVPN", providerBundleID: xray.providerBundleID)
        let (service, _) = makeService([ours])
        let tunnel = try #require(service.tunnels.first)
        let theirs = FakeTunnelProfile(name: "DVPN", providerBundleID: "com.example.other-ne", status: .connected)

        service.profileStatusDidChange(theirs)

        #expect(tunnel.status == .disconnected)
    }

    // MARK: Helpers

    /// A service over `profiles`, with each profile, and each one the store makes, reporting its status changes to it.
    private func makeService(_ profiles: [FakeTunnelProfile] = []) -> (TunnelsService, FakeTunnelProfileStore) {
        let store = FakeTunnelProfileStore()
        store.profiles = profiles
        let service = TunnelsService(tunnelProviders: profiles, store: store, clock: StepClock())
        let report: (FakeTunnelProfile) -> Void = { [weak service] in service?.profileStatusDidChange($0) }
        profiles.forEach { $0.onStatusChange = report }
        let previousOnMake = store.onMake
        store.onMake = { profile in
            profile.onStatusChange = report
            previousOnMake?(profile)
        }
        return (service, store)
    }
}
