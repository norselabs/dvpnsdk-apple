//
//  TunnelManagerNodeSwitchTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNSDK
@testable import DVPNTunnel
import DVPNWireGuardCore
import DVPNXRayCore
import Foundation
import NetworkExtension
import Testing
import WireGuardKit

extension ConfigurationFileSuites {
    /// `TunnelManager.switchNode(to:)` against fake profiles. A running tunnel changes nodes inside its extension when the
    /// node needs the same engine: nothing stops or starts, the new node's configuration is stored where the extension
    /// reads it, and a failure leaves the tunnel up. Anything else starts the tunnel again from the credentials.
    @MainActor
    struct TunnelManagerNodeSwitchTests {
        private let wireGuard = TunnelProtocolDescriptor(
            id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
        )
        private let xray = TunnelProtocolDescriptor(
            id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate
        )
        private let hysteria = TunnelProtocolDescriptor(
            id: .hysteria, providerBundleID: "com.example.vpn.hysteria-ne", tunnelName: "Hysteria", readiness: .immediate
        )
        private let switchMessage = TunnelProviderMessage.switchNode.data
        private let handshakeDone = Data("public_key=abc\nlast_handshake_time_sec=1790000000\n".utf8)
        private let noHandshake = Data("public_key=abc\nlast_handshake_time_sec=0\nrx_bytes=0\n".utf8)

        init() {
            DVPNCore.bootstrap(DVPNCoreConfiguration(appGroupID: "group.com.example.vpn.tests", protocols: [wireGuard, xray]))
            TemporaryConfigDirectory.use()
        }

        // MARK: In place

        @Test
        func aWireGuardNodeChangesInsideTheRunningTunnel() async throws {
            let profile = connectedProfile(wireGuard)
            profile.messageAnswer = handshakeDone
            profile.messageAnswers[switchMessage] = NodeSwitchReply.switched.data
            let manager = makeManager([profile])

            try await manager.switchNode(to: wireGuardCredentials(host: "203.0.113.21"))

            #expect(profile.stops == 0)
            #expect(profile.starts == 0)
            #expect(profile.isOnDemandEnabled)
            #expect(profile.messages.first == switchMessage)
            let stored = try #require(NETunnelProviderProtocol().asTunnelConfiguration())
            #expect(stored.peers.first?.endpoint?.stringRepresentation == "203.0.113.21:51820")
        }

        /// A new node that never answers leaves the tunnel up, holding the traffic until the app switches again or stops.
        @Test
        func aWireGuardNodeWithoutAHandshakeLeavesTheTunnelUp() async throws {
            let profile = connectedProfile(wireGuard)
            profile.messageAnswer = noHandshake
            profile.messageAnswers[switchMessage] = NodeSwitchReply.switched.data
            let manager = makeManager([profile])

            await #expect(throws: TunnelsServiceError.activationFailed(.handshakeTimedOut)) {
                try await manager.switchNode(to: wireGuardCredentials(host: "203.0.113.22"))
            }
            #expect(profile.stops == 0)
            #expect(profile.isOnDemandEnabled)
        }

        /// The switch reports `.reasserting` while the engine changes peers; the wait for the handshake outlasts it.
        @Test
        func theWaitForTheHandshakeOutlastsTheSwitchsReasserting() async throws {
            let profile = connectedProfile(wireGuard)
            profile.messageAnswer = handshakeDone
            profile.messageAnswers[switchMessage] = NodeSwitchReply.switched.data
            profile.onMessage = { [switchMessage] message in
                profile.report(message == switchMessage ? .reasserting : .connected)
            }
            let manager = makeManager([profile])

            try await manager.switchNode(to: wireGuardCredentials(host: "203.0.113.23"))

            #expect(profile.messages.first == switchMessage)
            #expect(profile.messages.dropFirst().contains(TunnelProviderMessage.runtimeConfiguration.data))
            #expect(profile.stops == 0)
        }

        @Test
        func anXrayNodeChangesInsideTheRunningTunnel() async throws {
            let profile = connectedProfile(xray)
            profile.messageAnswers[switchMessage] = NodeSwitchReply.switched.data
            let manager = makeManager([profile])

            try await manager.switchNode(to: xrayCredentials(host: "203.0.113.24"))

            #expect(profile.stops == 0)
            #expect(profile.starts == 0)
            #expect(profile.messages == [switchMessage])
            switch try XraySourceStore.loadCurrent() {
            case let .model(model):
                #expect(model.outbound.address == "203.0.113.24")
            }
        }

        @Test
        func aHysteriaNodeChangesInsideTheRunningTunnel() async throws {
            let profile = connectedProfile(hysteria)
            profile.messageAnswers[switchMessage] = NodeSwitchReply.switched.data
            let manager = makeManager([profile])

            try await manager.switchNode(to: hysteriaCredentials(host: "203.0.113.25"))

            #expect(profile.stops == 0)
            #expect(profile.starts == 0)
            #expect(try HysteriaConfigurationStore.loadCurrent().server == "203.0.113.25")
        }

        /// The extension's reason reaches the error, and the tunnel stays up.
        @Test
        func anEngineThatCannotStartOnTheNodeLeavesTheTunnelUp() async throws {
            let profile = connectedProfile(xray)
            profile.messageAnswers[switchMessage] = NodeSwitchReply.failed("no valid outbound found").data
            let manager = makeManager([profile])

            await #expect {
                try await manager.switchNode(to: xrayCredentials(host: "203.0.113.26"))
            } throws: { error in
                guard case .activationFailed(.startingFailed) = error as? TunnelsServiceError else { return false }
                return "\(error)".contains("no valid outbound found")
            }
            #expect(profile.stops == 0)
            #expect(profile.isOnDemandEnabled)
        }

        // MARK: Full start

        @Test
        func anotherEngineStartsTheTunnelAgain() async throws {
            let profile = connectedProfile(xray)
            profile.messageAnswer = handshakeDone
            let manager = makeManager([profile])

            try await manager.switchNode(to: wireGuardCredentials(host: "203.0.113.27"))

            #expect(!profile.messages.contains(switchMessage))
            #expect(profile.stops == 1)
            #expect(profile.starts == 1)
            #expect(profile.provider?.providerBundleIdentifier == wireGuard.providerBundleID)
        }

        @Test
        func aTunnelThatIsDownStartsOnTheNode() async throws {
            let profile = FakeTunnelProfile(name: wireGuard.tunnelName, providerBundleID: wireGuard.providerBundleID)
            profile.messageAnswer = handshakeDone
            let manager = makeManager([profile])

            try await manager.switchNode(to: wireGuardCredentials(host: "203.0.113.28"))

            #expect(!profile.messages.contains(switchMessage))
            #expect(profile.stops == 0)
            #expect(profile.starts == 1)
        }

        /// An extension built before node switching answers nothing: the tunnel starts again on the node.
        @Test
        func anExtensionThatCannotSwitchStartsTheTunnelAgain() async throws {
            let profile = connectedProfile(wireGuard)
            profile.messageAnswer = handshakeDone
            let manager = makeManager([profile])

            try await manager.switchNode(to: wireGuardCredentials(host: "203.0.113.29"))

            #expect(profile.messages.first == switchMessage)
            #expect(profile.stops == 1)
            #expect(profile.starts == 1)
            let stored = try #require(NETunnelProviderProtocol().asTunnelConfiguration())
            #expect(stored.peers.first?.endpoint?.stringRepresentation == "203.0.113.29:51820")
        }

        // MARK: Helpers

        /// A profile whose tunnel is up, as a start leaves it: on-demand on.
        private func connectedProfile(_ descriptor: TunnelProtocolDescriptor) -> FakeTunnelProfile {
            let profile = FakeTunnelProfile(name: descriptor.tunnelName, providerBundleID: descriptor.providerBundleID, status: .connected)
            profile.isOnDemandEnabled = true
            return profile
        }

        /// A manager over a service of fake profiles that report their status changes to it, in an app with all three
        /// engines.
        private func makeManager(_ profiles: [FakeTunnelProfile]) -> TunnelManager {
            let store = FakeTunnelProfileStore()
            store.profiles = profiles
            let service = TunnelsService(tunnelProviders: profiles, store: store, clock: StepClock())
            profiles.forEach { $0.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) } }
            let manager = TunnelManager(
                settings: FakeTunnelSettings(),
                configuration: DVPNCoreConfiguration(appGroupID: "group.com.example.vpn.tests", protocols: [wireGuard, xray, hysteria])
            )
            manager.attach(service)
            return manager
        }

        private func wireGuardCredentials(host: String) -> ConnectionCredentials {
            let node = WireGuardEndpoint(
                host: host, port: 51820, clientAddress: "10.8.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
            )
            return ConnectionCredentials(nodeType: .wireguard, endpoint: .wireGuard(node), privateKey: "oK56DE9Ue9zHAt61A8xBeLjd9zLOUlGmk8hYB7sTf1k=")
        }

        private func xrayCredentials(host: String) -> ConnectionCredentials {
            let reality = XrayInbound.Reality(
                serverName: "www.apple.com", shortID: "0123456789abcdef", publicKey: "SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q", fingerprint: "chrome"
            )
            let inbound = XrayInbound(port: 38808, proxyProtocol: .vless, transport: .tcp, security: .reality, flow: .vision, reality: reality)
            return ConnectionCredentials(
                nodeType: .xray, endpoint: .xrayNode(XrayNodeEndpoint(host: host, inbounds: [inbound])), uid: "11111111-2222-3333-4444-555555555555"
            )
        }

        private func hysteriaCredentials(host: String) -> ConnectionCredentials {
            ConnectionCredentials(nodeType: .hysteria, endpoint: .hysteria(HysteriaEndpoint(host: host, port: 17435, tlsPin: "ab")), uid: "client")
        }
    }
}
