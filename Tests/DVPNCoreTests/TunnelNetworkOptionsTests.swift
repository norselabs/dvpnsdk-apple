//
//  TunnelNetworkOptionsTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing
import WireGuardKit

extension ConfigurationFileSuites {
    /// The network options on every engine's profile: the defaults leave each profile as the SDK always made it, and the
    /// kill switch reaches the WireGuard profile and the proxy engines' alike.
    ///
    /// The WireGuard profile stores its configuration file, so the suite runs serially in a temporary directory.
    @MainActor
    @Suite(.serialized)
    struct TunnelNetworkOptionsTests {
        private let killSwitch = TunnelNetworkOptions(includeAllNetworks: true, excludeLocalNetworks: false, enforceRoutes: true)
        private let xray = TunnelProtocolDescriptor(
            id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate
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
            TemporaryConfigDirectory.use()
        }

        // MARK: Protocol

        @Test
        func theDefaultsLeaveAProtocolAsTheSystemMakesIt() {
            let untouched = NETunnelProviderProtocol()
            let applied = NETunnelProviderProtocol()

            applied.apply(.default)

            #expect(!applied.includeAllNetworks)
            #expect(!applied.enforceRoutes)
            #expect(applied.excludeLocalNetworks == untouched.excludeLocalNetworks)
            #expect(untouched.carries(.default))
        }

        @Test
        func theOptionsOwnChoiceWinsOverTheEngines() {
            let applied = NETunnelProviderProtocol()

            applied.apply(killSwitch, excludingLocalNetworksByDefault: true)

            #expect(applied.includeAllNetworks)
            #expect(!applied.excludeLocalNetworks)
            #expect(applied.enforceRoutes)
            #expect(applied.carries(killSwitch, excludingLocalNetworksByDefault: true))
            #expect(!applied.carries(.default, excludingLocalNetworksByDefault: true))
        }

        @Test(arguments: [true, false])
        func withoutAChoiceTheEnginesIsWritten(_ engineDefault: Bool) {
            let applied = NETunnelProviderProtocol()

            applied.apply(.default, excludingLocalNetworksByDefault: engineDefault)

            #expect(applied.excludeLocalNetworks == engineDefault)
        }

        @Test
        func theOptionsRoundTripThroughCodable() throws {
            let options = TunnelNetworkOptions(includeAllNetworks: true, excludeLocalNetworks: false, enforceRoutes: true, ipv6: .tunnel)

            let decoded = try JSONDecoder().decode(TunnelNetworkOptions.self, from: JSONEncoder().encode(options))

            #expect(decoded == options)
        }

        /// Options an app stored before an option existed decode with that option's default.
        @Test
        func aMissingOptionDecodesAsItsDefault() throws {
            let decoded = try JSONDecoder().decode(TunnelNetworkOptions.self, from: Data(#"{"includeAllNetworks":true}"#.utf8))

            #expect(decoded == TunnelNetworkOptions(includeAllNetworks: true))
            #expect(try JSONDecoder().decode(TunnelNetworkOptions.self, from: Data("{}".utf8)) == .default)
        }

        // MARK: Profiles

        @Test
        func aProxyProfileKeepsLocalNetworksOutByDefault() async throws {
            let (service, store) = makeService()

            _ = try await service.startProxyTunnel(xray, onDemandEnabled: true)

            let provider = try #require(store.made.first?.provider)
            #expect(provider.excludeLocalNetworks, "as the proxy engines always had it")
            #expect(!provider.includeAllNetworks)
            #expect(!provider.enforceRoutes)
        }

        @Test
        func aProxyProfileCarriesTheKillSwitch() async throws {
            let (service, store) = makeService()

            _ = try await service.startProxyTunnel(xray, onDemandEnabled: true, networkOptions: killSwitch)

            let provider = try #require(store.made.first?.provider)
            #expect(provider.includeAllNetworks)
            #expect(!provider.excludeLocalNetworks)
            #expect(provider.enforceRoutes)
        }

        @Test
        func aWireGuardProfileCarriesTheKillSwitch() async throws {
            let (service, store) = makeService()

            _ = try await service.add(tunnelConfiguration: try wireGuardConfiguration(), onDemandEnabled: true, networkOptions: killSwitch)

            let provider = try #require(store.made.first?.provider)
            #expect(provider.providerBundleIdentifier == "com.example.vpn.wireguard-ne")
            #expect(provider.includeAllNetworks)
            #expect(!provider.excludeLocalNetworks)
            #expect(provider.enforceRoutes)
        }

        /// A running tunnel keeps the options it started with: a change stops it, and the caller starts it again.
        @Test
        func changedOptionsStopARunningWireGuardTunnel() async throws {
            let configuration = try wireGuardConfiguration()
            let profile = FakeTunnelProfile(name: "WireGuard", status: .connected)
            profile.set(tunnelConfiguration: configuration)
            let (service, _) = makeService([profile])
            let tunnel = try #require(service.tunnels.first)

            try await service.modify(tunnel: tunnel, isOnDemandEnabled: true, tunnelConfiguration: configuration, networkOptions: killSwitch)

            #expect(profile.stops == 1)
            #expect(profile.provider?.includeAllNetworks == true)
        }

        @Test
        func unchangedOptionsLeaveARunningWireGuardTunnelUp() async throws {
            let configuration = try wireGuardConfiguration()
            let profile = FakeTunnelProfile(name: "WireGuard", status: .connected)
            profile.set(tunnelConfiguration: configuration, networkOptions: killSwitch)
            let (service, _) = makeService([profile])
            let tunnel = try #require(service.tunnels.first)

            try await service.modify(tunnel: tunnel, isOnDemandEnabled: true, tunnelConfiguration: configuration, networkOptions: killSwitch)

            #expect(profile.stops == 0)
        }

        /// The same WireGuard configuration on a profile that a proxy engine rewrote still points it back at WireGuard.
        @Test
        func aProfileOnAnotherEnginesExtensionIsRewritten() async throws {
            let configuration = try wireGuardConfiguration()
            let profile = FakeTunnelProfile(name: "WireGuard", status: .connected)
            profile.set(tunnelConfiguration: configuration)
            profile.provider?.providerBundleIdentifier = xray.providerBundleID
            let (service, _) = makeService([profile])
            let tunnel = try #require(service.tunnels.first)

            try await service.modify(tunnel: tunnel, isOnDemandEnabled: true, tunnelConfiguration: configuration)

            #expect(profile.provider?.providerBundleIdentifier == "com.example.vpn.wireguard-ne")
            #expect(profile.stops == 1)
        }

        // MARK: Manager

        @Test
        func theManagerHandsTheSettingsOptionsToTheProfile() async throws {
            let (service, store) = makeService()
            let hysteria = TunnelProtocolDescriptor(
                id: .hysteria, providerBundleID: "com.example.vpn.hysteria-ne", tunnelName: "Hysteria", readiness: .immediate
            )
            let manager = TunnelManager(
                settings: FakeTunnelSettings(networkOptions: killSwitch),
                configuration: DVPNCoreConfiguration(appGroupID: "group.com.example.vpn.tests", protocols: [hysteria])
            )
            manager.attach(service)

            try await manager.startHysteria(
                configuration: HysteriaConfiguration(server: "203.0.113.6", port: 17435, auth: "client"),
                descriptor: hysteria
            )

            let provider = try #require(store.made.first?.provider)
            #expect(provider.includeAllNetworks)
            #expect(!provider.excludeLocalNetworks)
            #expect(provider.enforceRoutes)
        }

        /// The proxy extensions take IPv6 from what the app stored at the start.
        @Test
        func aProxyStartStoresTheIPv6Mode() async throws {
            let hysteria = TunnelProtocolDescriptor(
                id: .hysteria, providerBundleID: "com.example.vpn.hysteria-ne", tunnelName: "Hysteria", readiness: .immediate
            )
            let manager = TunnelManager(
                settings: FakeTunnelSettings(networkOptions: TunnelNetworkOptions(ipv6: .tunnel)),
                configuration: DVPNCoreConfiguration(appGroupID: "group.com.example.vpn.tests", protocols: [hysteria])
            )
            manager.attach(makeService().0)

            try await manager.startHysteria(configuration: HysteriaConfiguration(server: "203.0.113.6"), descriptor: hysteria)

            #expect(TunnelConfigDirectories.network().ipv6Enabled)
        }

        // MARK: Helpers

        private func wireGuardConfiguration() throws -> TunnelConfiguration {
            try TunnelConfiguration(
                fromWgQuickConfig: """
                [Interface]
                PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
                Address = 10.8.1.2/32
                DNS = 1.1.1.1, 1.0.0.1

                [Peer]
                PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
                AllowedIPs = 0.0.0.0/0
                Endpoint = 203.0.113.10:51820
                PersistentKeepalive = 25
                """,
                called: "WireGuard"
            )
        }

        /// A service over fake profiles that report their status changes to it.
        private func makeService(_ profiles: [FakeTunnelProfile] = []) -> (TunnelsService, FakeTunnelProfileStore) {
            let store = FakeTunnelProfileStore()
            store.profiles = profiles
            let service = TunnelsService(tunnelProviders: profiles, store: store, clock: StepClock())
            profiles.forEach { $0.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) } }
            store.onMake = { [weak service] made in made.onStatusChange = { service?.profileStatusDidChange($0) } }
            return (service, store)
        }
    }
}
