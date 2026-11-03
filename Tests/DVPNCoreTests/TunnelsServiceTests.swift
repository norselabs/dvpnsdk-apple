//
//  TunnelsServiceTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing
import WireGuardKitTypes

/// The tunnel service against fake profiles: one profile for every engine, activation and its
/// failures, stopping, and profiles changed outside the app. `StepClock` makes every timeout elapse at once.
@MainActor
struct TunnelsServiceTests {
    private let xray = TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate)
    private let hysteria = TunnelProtocolDescriptor(
        id: .hysteria, providerBundleID: "com.example.vpn.hysteria-ne", tunnelName: "Hysteria", readiness: .immediate
    )
    private let wireGuardConfig = """
    [Interface]
    PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
    Address = 10.8.1.2/32
    DNS = 1.1.1.1

    [Peer]
    PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
    AllowedIPs = 0.0.0.0/0
    Endpoint = 203.0.113.10:51820
    PersistentKeepalive = 25
    """

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

    /// A proxy start leaves the WireGuard file as it was, so a WireGuard start can bring back the same configuration while
    /// the profile still points at the proxy's extension: the profile goes back to WireGuard's, and the proxy's running
    /// tunnel stops for the caller to start WireGuard's.
    @Test
    func aWireGuardStartAfterAProxyOneLeavesTheProxysExtension() async throws {
        try await withConfigurationFilesOfItsOwn {
            let configuration = try TunnelConfiguration(fromWgQuickConfig: wireGuardConfig, called: "WireGuard")
            let (service, store) = makeService()
            let tunnel = try await service.add(tunnelConfiguration: configuration, onDemandEnabled: true)
            _ = try await service.startProxyTunnel(xray, onDemandEnabled: true)
            try await service.startActivation(of: tunnel)

            try await service.modify(tunnel: tunnel, isOnDemandEnabled: true, tunnelConfiguration: configuration)

            let profile = try #require(store.made.first)
            #expect(profile.provider?.providerBundleIdentifier == "com.example.vpn.wireguard-ne")
            #expect(profile.savedProviderBundleIDs.last == "com.example.vpn.wireguard-ne")
            #expect(profile.localizedDescription == "WireGuard")
            #expect(profile.stops == 1)
            #expect(tunnel.status == .disconnected)
        }
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

    /// Runs `body` with the configuration files in a directory of their own, removed afterwards: a test process cannot
    /// write the App Group container.
    private func withConfigurationFilesOfItsOwn(_ body: () async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await TunnelConfigDirectories.$homeDirectoryOverride.withValue(directory) {
            try await body()
        }
    }

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
