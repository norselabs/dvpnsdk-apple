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
    /// The extensions of the app under test. Only its manager gets them: the process keeps the configuration every suite
    /// bootstraps, which declares WireGuard.
    private let xrayOnly = DVPNCoreConfiguration(
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

    /// The profile's initializer reads the process's configuration, so this app's runs in a process of its own.
    @Test
    func aWireGuardProfileIsNotMade() async {
        await #expect(processExitsWith: .success) {
            DVPNCore.bootstrap(
                DVPNCoreConfiguration(
                    appGroupID: "group.com.example.vpn.tests",
                    protocols: [
                        TunnelProtocolDescriptor(
                            id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate
                        ),
                    ]
                )
            )
            let configuration = TunnelConfiguration(
                name: "WireGuard", interface: InterfaceConfiguration(privateKey: PrivateKey()), peers: []
            )
            if NETunnelProviderProtocol(tunnelConfiguration: configuration) != nil {
                exit(EXIT_FAILURE)
            }
        }
    }

    private func makeManager() -> TunnelManager {
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: xrayOnly)
        manager.attach(TunnelsService(tunnelProviders: [], store: FakeTunnelProfileStore(), clock: StepClock()))
        return manager
    }
}
