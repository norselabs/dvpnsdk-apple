//
//  DocumentValidationTests.swift
//  DVPNCore
//
//  Every typed model must produce a document that Xray-core's own config builder accepts.
//  Xray-core 26.x rules exercised here: `allowInsecure` no longer exists; plaintext VLESS/Trojan is
//  only allowed towards private addresses; REALITY only over RAW (tcp), XHTTP and gRPC.
//

import DVPNCoreKit
@testable import DVPNXRayCore
@testable import DVPNXRayProvider
import Foundation
import Testing

extension LibXrayTests {
    @Suite(.serialized)
    struct DocumentValidationTests {
        init() {
            DVPNCore.bootstrap(
                DVPNCoreConfiguration(
                    appGroupID: "group.com.example.vpn.tests",
                    protocols: [
                        TunnelProtocolDescriptor(id: .wireGuard, providerBundleID: "wg", tunnelName: "WireGuard", readiness: .wireGuardHandshake),
                        TunnelProtocolDescriptor(id: .xray, providerBundleID: "xray", tunnelName: "Xray", readiness: .immediate),
                    ]
                )
            )
        }

        private let uuid = "11111111-2222-3333-4444-555555555555"
        private let publicKey = "SOJ1ByzX8rQZ6KJ7z5nY2F9A4fVpzB0rQdL6wMhzk9Q"

        private func outbounds(address: String) -> [XOutbound] {
            [
                .vmess(VMess(address: address, port: 443, users: [VMess.User(id: uuid)])),
                .vless(VLESS(address: address, port: 443, users: [VLESS.User(id: uuid)])),
                .trojan(Trojan(address: address, port: 443, password: "secret")),
            ]
        }

        private let transports: [XTransport] = [
            .tcp(.init()),
            .ws(.init(path: "/ws", headers: ["Host": "example.com"])),
            .grpc(.init(serviceName: "svc")),
            .xhttp(.init(host: "cdn.example.com", path: "/x", mode: .packetUp)),
            .httpupgrade(.init(host: "example.com", path: "/up")),
        ]

        private func assertBuilds(_ model: XConfigurationModel, sourceLocation: SourceLocation = #_sourceLocation) throws {
            let document = try model.buildConfigurationData(localProxy: .fixture)
            #expect(
                throws: Never.self,
                "\(model.outbound.protocolName) / \(model.transport.network) / \(model.security.kind)",
                sourceLocation: sourceLocation
            ) {
                try XrayInvoke.testXray(configJSON: String(decoding: document, as: UTF8.self))
            }
        }

        @Test
        func plaintextCombinationsBuildTowardsPrivateAddresses() throws {
            for outbound in outbounds(address: "192.168.1.10") {
                for transport in transports {
                    try assertBuilds(XConfigurationModel(outbound: outbound, transport: transport, security: .none))
                }
            }
        }

        @Test
        func tlsCombinationsBuild() throws {
            let tls = XSecurity.tls(.init(serverName: "example.com"))
            for outbound in outbounds(address: "example.com") {
                for transport in transports {
                    try assertBuilds(XConfigurationModel(outbound: outbound, transport: transport, security: tls))
                }
            }
            let pinned = XSecurity.tls(.init(serverName: "example.com", pinnedPeerCertSha256: String(repeating: "ab", count: 32)))
            try assertBuilds(XConfigurationModel(outbound: outbounds(address: "example.com")[0], transport: .tcp(.init()), security: pinned))
        }

        /// The backend shape after `XraySecurityResolver`: a bare IP as address (and SNI) with the observed pin.
        @Test
        func pinnedTLSTowardsIPLiteralBuilds() throws {
            let pin = String(repeating: "ab", count: 32)
            let vmess = XOutbound.vmess(VMess(address: "203.0.113.5", port: 443, users: [VMess.User(id: uuid)]))
            for serverName in ["203.0.113.5", ""] {
                let pinned = XSecurity.tls(.init(serverName: serverName, pinnedPeerCertSha256: pin))
                for transport in transports {
                    try assertBuilds(XConfigurationModel(outbound: vmess, transport: transport, security: pinned))
                }
            }
        }

        @Test
        func autodetectNeverReachesXray() {
            let model = XConfigurationModel(outbound: outbounds(address: "203.0.113.5")[0], security: .autodetect(.init(serverName: "203.0.113.5")))
            #expect(throws: XConfigurationError.unresolvedSecurity) { try model.buildConfigurationData(localProxy: .fixture) }
        }

        @Test
        func realityBuildsOverRawXHTTPAndGRPCOnly() throws {
            let reality = XSecurity.reality(.init(serverName: "www.microsoft.com", publicKey: publicKey, shortId: "0123ab"))
            for outbound in outbounds(address: "example.com") {
                for transport in [XTransport.tcp(.init()), .xhttp(.init(host: "cdn.example.com", path: "/x")), .grpc(.init(serviceName: "svc"))] {
                    try assertBuilds(XConfigurationModel(outbound: outbound, transport: transport, security: reality))
                }
                for transport in [XTransport.ws(.init()), .httpupgrade(.init())] {
                    let model = XConfigurationModel(outbound: outbound, transport: transport, security: reality)
                    let document = try model.buildConfigurationData(localProxy: .fixture)
                    #expect(throws: (any Error).self, "REALITY over \(transport.network) is rejected by Xray-core") {
                        try XrayInvoke.testXray(configJSON: String(decoding: document, as: UTF8.self))
                    }
                }
            }
        }

        @Test
        func plaintextVLESSToPublicAddressIsRejected() throws {
            let document = try XConfigurationModel(outbound: outbounds(address: "example.com")[1]).buildConfigurationData(localProxy: .fixture)
            #expect(throws: (any Error).self) { try XrayInvoke.testXray(configJSON: String(decoding: document, as: UTF8.self)) }
        }

        /// "Advanced obfuscation": `sockopt.dialerProxy` towards a `freedom` outbound with `fragment` settings.
        @Test
        func tlsFragmentObfuscationBuilds() throws {
            let fragment = XObfuscation.tlsFragment(.init())
            let tls = XSecurity.tls(.init(serverName: "example.com"))
            for outbound in outbounds(address: "example.com") {
                for transport in transports {
                    try assertBuilds(XConfigurationModel(outbound: outbound, transport: transport, security: tls, obfuscation: fragment))
                }
            }
            let reality = XSecurity.reality(.init(serverName: "www.microsoft.com", publicKey: publicKey, shortId: "0123ab"))
            try assertBuilds(
                XConfigurationModel(outbound: outbounds(address: "example.com")[1], transport: .tcp(.init()), security: reality, obfuscation: fragment)
            )
            // Plaintext streams carry the dialer too; `tlshello` simply never matches.
            try assertBuilds(
                XConfigurationModel(outbound: outbounds(address: "192.168.1.10")[0], transport: .tcp(.init()), security: .none, obfuscation: fragment)
            )
        }

        @Test
        func visionFlowBuilds() throws {
            let model = XConfigurationModel(
                outbound: .vless(VLESS(address: "example.com", port: 443, users: [VLESS.User(id: uuid, flow: .xtlsRprxVision)])),
                transport: .tcp(.init()),
                security: .reality(.init(serverName: "www.microsoft.com", publicKey: publicKey, shortId: "0123ab"))
            )
            try assertBuilds(model)
        }
    }
}
