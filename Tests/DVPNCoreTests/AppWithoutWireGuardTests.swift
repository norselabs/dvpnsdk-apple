//
//  AppWithoutWireGuardTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import DVPNWireGuardCore
import Foundation
import NetworkExtension
import Testing
import WireGuardKitTypes

/// An app that declares no WireGuard extension: its WireGuard credentials and profiles are refused, as an undeclared
/// Xray or Hysteria is, instead of stopping the app.
@MainActor
struct AppWithoutWireGuardTests {
    /// The extensions of the app under test. In this process only its manager gets them, as the process keeps the
    /// configuration every suite bootstraps, which declares WireGuard; the tests in a process of their own bootstrap them.
    private nonisolated static let xrayOnly = DVPNCoreConfiguration(
        appGroupID: "group.com.example.vpn.tests",
        protocols: [
            TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
        ]
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

    /// Loading the tunnels, which a launch's `isActive()` does, prepares the WireGuard model.
    @Test
    func theManagerLoadsItsTunnels() async {
        let manager = makeManager()

        #expect(await manager.isActive() == false)
    }

    @Test(arguments: [NodeType.wireguard, .amneziawg])
    func wireGuardCredentialsAreAnUnsupportedProtocol(nodeType: NodeType) async {
        let manager = makeManager()
        let node = WireGuardEndpoint(
            host: "203.0.113.10", port: 51820, clientAddress: "10.10.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
        )
        let endpoint: ConnectionEndpoint = nodeType == .wireguard
            ? .wireGuard(node)
            : .amneziaWG(AmneziaWGEndpoint(wireGuard: node, parameters: [:]))
        let credentials = ConnectionCredentials(
            nodeType: nodeType, endpoint: endpoint, privateKey: "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U="
        )

        await #expect(throws: TunnelsServiceError.unsupportedProtocol) {
            try await manager.start(from: credentials)
        }
    }

    /// The profile's initializer reads the process's configuration, so this app's runs in a process of its own. The
    /// configuration file would go to a directory the test can write, so only the missing extension can refuse it.
    @Test
    func aWireGuardProfileIsNotMade() async {
        await #expect(processExitsWith: .success) {
            DVPNCore.bootstrap(Self.xrayOnly)
            let directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = TunnelConfiguration(
                name: "WireGuard", interface: InterfaceConfiguration(privateKey: PrivateKey()), peers: []
            )
            let made = TunnelConfigDirectories.$homeDirectoryOverride.withValue(directory) {
                NETunnelProviderProtocol(tunnelConfiguration: configuration) != nil
            }
            let written = FileManager.default.subpaths(atPath: directory.path)?.contains { $0.hasSuffix("config.json") } ?? false
            if made || written {
                exit(EXIT_FAILURE)
            }
        }
    }

    /// A launch in a process that declares only Xray: the tunnels load, a profile on a WireGuard extension included,
    /// and WireGuard credentials are refused, with nothing stopping the app.
    @Test
    func aLaunchLoadsItsTunnelsAndRefusesWireGuard() async {
        await #expect(processExitsWith: .success) {
            DVPNCore.bootstrap(Self.xrayOnly)
            if await !Self.launchLoadsAndRefusesWireGuard() {
                exit(EXIT_FAILURE)
            }
        }
    }

    /// What a launch does first: the service loads the system's profiles, the manager checks whether one is up, and a
    /// connect with WireGuard credentials follows.
    private static func launchLoadsAndRefusesWireGuard() async -> Bool {
        let store = FakeTunnelProfileStore()
        store.profiles = [FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")]
        guard let service = try? await TunnelsService.create(store: store, clock: StepClock()) else { return false }
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: xrayOnly)
        manager.attach(service)
        guard await manager.isActive() == false else { return false }
        let credentials = ConnectionCredentials(
            nodeType: .wireguard,
            endpoint: .wireGuard(WireGuardEndpoint(
                host: "203.0.113.10", port: 51820, clientAddress: "10.10.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
            )),
            privateKey: "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U="
        )
        do {
            try await manager.start(from: credentials)
            return false
        } catch {
            return error == .unsupportedProtocol
        }
    }

    private func makeManager() -> TunnelManager {
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: Self.xrayOnly)
        manager.attach(TunnelsService(tunnelProviders: [], store: FakeTunnelProfileStore(), clock: StepClock()))
        return manager
    }
}
