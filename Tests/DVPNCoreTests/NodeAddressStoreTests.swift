//
//  NodeAddressStoreTests.swift
//  DVPNSDK
//

@testable import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import Testing

/// A start's log lines name the node's address; the app stores it for the extension's line.
struct NodeAddressStoreTests {
    /// One fixed suite, so a run leaves no new preferences file behind.
    private let suiteName = "com.example.vpn.tests.node-address"

    /// A start without an address forgets the previous one, so no line names another node.
    @Test
    func anAddressIsKeptUntilAStartWithoutOne() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        NodeAddressStore.record("sentnode1qx7example", in: defaults)
        #expect(NodeAddressStore.load(from: defaults) == "sentnode1qx7example")

        NodeAddressStore.record(nil, in: defaults)
        #expect(NodeAddressStore.load(from: defaults) == nil)

        NodeAddressStore.record("sentnode1qx7example", in: defaults)
        NodeAddressStore.record("", in: defaults)
        #expect(NodeAddressStore.load(from: defaults) == nil)
    }

    @Test
    func theExtensionsLineNamesTheStoredAddress() throws {
        // A suite of its own: the tests run in parallel.
        let suiteName = suiteName + ".line"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            NodeAddressStore.startLine(host: "203.0.113.10", in: defaults)
                == "Starting the tunnel to the node at 203.0.113.10 (no node address)"
        )

        NodeAddressStore.record("sentnode1qx7example", in: defaults)
        #expect(
            NodeAddressStore.startLine(host: "203.0.113.10", in: defaults)
                == "Starting the tunnel to the node at 203.0.113.10 (sentnode1qx7example)"
        )
        #expect(
            NodeAddressStore.startLine(host: nil, in: defaults)
                == "Starting the tunnel to the node at an unknown host (sentnode1qx7example)"
        )
    }

    @Test
    func theAppsLineNamesTheNodeTypeTheHostAndTheAddress() {
        let endpoint = ConnectionEndpoint.v2ray(V2RayNodeEndpoint(host: "node.example.com", inbounds: []))
        let server = Server(
            id: "srv-1", countryID: "DE", cityID: "c-1", name: "Berlin 1", isAvailable: true, serverProtocol: "V2RAY",
            address: "sentnode1qx7example"
        )

        #expect(
            TunnelManager.startLine(for: ConnectionCredentials(nodeType: .v2ray, endpoint: endpoint, server: server))
                == "Starting the tunnel to the V2RAY node at node.example.com (sentnode1qx7example)"
        )
        #expect(
            TunnelManager.startLine(for: ConnectionCredentials(nodeType: .v2ray, endpoint: endpoint))
                == "Starting the tunnel to the V2RAY node at node.example.com (no node address)"
        )
    }
}
