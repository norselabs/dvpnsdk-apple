//
//  HysteriaNodeConfigurationTests.swift
//  DVPNCore
//

import DVPNHysteriaCore
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import Testing

/// How a backend Hysteria node becomes the client configuration (the SDK decodes, the tunnel layer decides).
struct HysteriaNodeConfigurationTests {
    @Test
    func pinnedNodeIsTrustedThroughItsPin() {
        let endpoint = HysteriaEndpoint(host: "203.0.113.6", port: 17435, obfsPassword: "salamander", tlsPin: "ab:cd")
        let configuration = TunnelManager.configuration(for: endpoint, uid: "uuid-1")

        #expect(configuration.server == "203.0.113.6")
        #expect(configuration.port == 17435)
        #expect(configuration.auth == "uuid-1", "the node names no auth of its own; the client's UUID is it")
        #expect(configuration.tls.insecure, "self-signed node certificates: the pin is the trust anchor, as in the node's client template")
        #expect(configuration.tls.pinSHA256 == "ab:cd")
        #expect(configuration.obfs == .init(password: "salamander"))
    }

    @Test
    func nodeValuesWinWhenSent() {
        let endpoint = HysteriaEndpoint(host: "h", port: 1, auth: "secret", sni: "example.com", insecure: true)
        let configuration = TunnelManager.configuration(for: endpoint, uid: "uuid-1")

        #expect(configuration.auth == "secret")
        #expect(configuration.tls.sni == "example.com")
        #expect(configuration.tls.insecure)
        #expect(configuration.tls.pinSHA256 == nil)
        #expect(configuration.obfs == nil, "no password, no Salamander")
    }

    @Test
    func unpinnedNodeWithoutTheFlagIsVerified() {
        let configuration = TunnelManager.configuration(for: HysteriaEndpoint(host: "h", port: 1), uid: nil)
        #expect(!configuration.tls.insecure)
        #expect(configuration.auth.isEmpty)
    }
}
