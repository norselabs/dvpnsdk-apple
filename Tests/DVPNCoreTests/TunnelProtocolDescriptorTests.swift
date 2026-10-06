//
//  TunnelProtocolDescriptorTests.swift
//  DVPNCore
//

@testable import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import Testing

struct TunnelProtocolDescriptorTests {
    private let wireGuard = TunnelProtocolDescriptor(
        id: .wireGuard,
        providerBundleID: "io.example.wireguard-ne",
        tunnelName: "WireGuard",
        readiness: .wireGuardHandshake
    )
    private let xray = TunnelProtocolDescriptor(
        id: .xray,
        providerBundleID: "io.example.v2ray-ne",
        tunnelName: "Xray",
        readiness: .immediate
    )

    @Test
    func lookupByIDAndBundleID() {
        let configuration = DVPNCoreConfiguration(appGroupID: "group.test", protocols: [wireGuard, xray])

        #expect(configuration.descriptor(for: .xray) == xray)
        #expect(configuration.descriptor(forProviderBundleID: "io.example.wireguard-ne") == wireGuard)
        #expect(configuration.descriptor(for: .hysteria) == nil)
        #expect(configuration.descriptor(forProviderBundleID: nil) == nil)
        #expect(configuration.descriptor(forProviderBundleID: "io.example.unknown") == nil)
        #expect(configuration.supports(.wireGuard))
    }

    @Test
    func nodeTypesMapOntoEngines() {
        #expect(NodeType.wireguard.tunnelProtocolID == .wireGuard)
        #expect(NodeType.amneziawg.tunnelProtocolID == .wireGuard, "AmneziaWG rides on the WireGuard engine")
        #expect(NodeType.xray.tunnelProtocolID == .xray)
        #expect(NodeType.hysteria.tunnelProtocolID == .hysteria)
        #expect(NodeType.v2ray.tunnelProtocolID == .xray)
        #expect(NodeType.v2ray.rawValue == "V2RAY", "legacy wire value stays")
        #expect(NodeType.xray.rawValue == "XRAY")
        #expect(NodeType.hysteria.rawValue == "HYSTERIA2")
        for id in TunnelProtocolID.allCases {
            #expect(NodeType.allCases.contains { $0.tunnelProtocolID == id }, "\(id) has no backend node type")
        }
    }
}
