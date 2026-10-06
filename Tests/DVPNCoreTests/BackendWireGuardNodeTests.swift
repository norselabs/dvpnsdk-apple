//
//  BackendWireGuardNodeTests.swift
//  DVPNCore
//

import DVPNSDK
@testable import DVPNTunnel
@testable import DVPNWireGuardCore
import Foundation
import Testing
import WireGuardKit

/// Regression: the tunnel model is seeded from the last stored configuration. After a manual
/// AmneziaWG import with a preshared key, backend WireGuard connections inherited that key and the
/// server's handshake responses were rejected ("Received invalid response message").
@MainActor
struct BackendWireGuardNodeTests {
    private let imported = """
    [Interface]
    PrivateKey = WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U=
    Address = 10.8.1.2/32
    DNS = 9.9.9.9
    MTU = 1280
    Jc = 4
    Jmin = 40
    Jmax = 70
    H1 = 1234567891

    [Peer]
    PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
    PresharedKey = FpCyhws9LHkfI4ZgHDrm6Z1mCkbbMv8oNvVU7nHDlIQ=
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = 203.0.113.10:51820
    PersistentKeepalive = 25
    """

    @Test
    func backendNodeClearsEverythingTheBackendDoesNotProvide() throws {
        let seeded = try TunnelConfiguration(fromWgQuickConfig: imported, called: "WireGuard")
        #expect(seeded.peers[0].preSharedKey != nil, "fixture must carry a preshared key")
        let model = TunnelModel(tunnelConfiguration: seeded)

        let privateKey = try #require(PrivateKey(base64Key: "oK56DE9Ue9zHAt61A8xBeLjd9zLOUlGmk8hYB7sTf1k="))
        let node = WireGuardEndpoint(
            host: "203.0.113.10", port: 51820, clientAddress: "10.10.0.2", peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
        )
        TunnelManager.configureBackendNode(model, privateKey: privateKey, endpoint: node, dns: "1.1.1.1, 1.0.0.1")

        let configuration = try model.save().get()
        let peer = configuration.peers[0]
        #expect(peer.preSharedKey == nil, "a manual import's preshared key must not leak into backend nodes")
        #expect(peer.publicKey.base64Key == node.peerPublicKey)
        #expect(peer.endpoint?.stringRepresentation == "203.0.113.10:51820")
        #expect(peer.allowedIPs.map(\.stringRepresentation) == ["0.0.0.0/0"])
        #expect(peer.persistentKeepAlive == "25")

        let interface = configuration.interface
        #expect(interface.privateKey.base64Key == privateKey.base64Key)
        #expect(interface.addresses.map(\.stringRepresentation) == ["10.10.0.2/32"])
        #expect(interface.listenPort == 51820)
        #expect(interface.mtu == nil)
        #expect(interface.dns.map(\.stringRepresentation) == ["1.1.1.1", "1.0.0.1"])
        #expect(!configuration.hasAmneziaWGParameters, "the model never carried AWG fields; make sure that stays true")

        // The exact text the extension will parse.
        let text = configuration.asWgQuickConfig()
        #expect(!text.contains("PresharedKey"))
        #expect(!text.contains("MTU"))
    }
}
