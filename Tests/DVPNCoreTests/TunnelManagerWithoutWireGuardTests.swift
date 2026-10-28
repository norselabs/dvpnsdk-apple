//
//  TunnelManagerWithoutWireGuardTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import Testing

/// An app that ships no WireGuard extension: its manager loads, and WireGuard credentials fail with
/// `.unsupportedProtocol` instead of trapping.
@MainActor
struct TunnelManagerWithoutWireGuardTests {
    /// What this app declares; the process-wide configuration stays the one the other suites bootstrap.
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

    /// Loading the service prepares the WireGuard model, which used to trap without a WireGuard descriptor.
    @Test
    func theManagerLoadsWithoutAWireGuardExtension() {
        let manager = makeManager()

        #expect(!manager.isTunnelActive)
    }

    @Test(arguments: [NodeType.wireguard, .amneziawg])
    func wireGuardCredentialsAreUnsupported(_ nodeType: NodeType) async {
        let manager = makeManager()
        let node = WireGuardEndpoint(
            host: "203.0.113.10", port: 51820, clientAddress: "10.8.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
        )
        let endpoint: ConnectionEndpoint = nodeType == .wireguard
            ? .wireGuard(node)
            : .amneziaWG(AmneziaWGEndpoint(wireGuard: node, parameters: [:]))
        let credentials = ConnectionCredentials(
            nodeType: nodeType, endpoint: endpoint, privateKey: "oK56DE9Ue9zHAt61A8xBeLjd9zLOUlGmk8hYB7sTf1k="
        )

        await #expect(throws: TunnelsServiceError.unsupportedProtocol) {
            try await manager.start(from: credentials)
        }
    }

    private func makeManager() -> TunnelManager {
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: xrayOnly)
        manager.attach(TunnelsService(tunnelProviders: [], store: FakeTunnelProfileStore(), clock: StepClock()))
        return manager
    }
}
