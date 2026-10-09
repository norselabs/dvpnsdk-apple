//
//  TunnelStateStoreTests.swift
//  DVPNCore
//

@testable import DVPNCoreKit
import Foundation
import Testing

/// The packet tunnels say whether they are up; the split-tunnel proxy acts only then.
struct TunnelStateStoreTests {
    /// One fixed suite, so a run leaves no new preferences file behind.
    private let suiteName = "com.example.vpn.tests.tunnel-state"

    @Test
    func theTunnelIsDownUntilItSaysOtherwise() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!TunnelStateStore.isUp(in: defaults))

        TunnelStateStore.record(isUp: true, in: defaults, notifying: false)
        #expect(TunnelStateStore.isUp(in: defaults))

        TunnelStateStore.record(isUp: false, in: defaults, notifying: false)
        #expect(!TunnelStateStore.isUp(in: defaults))
    }

    /// The node is kept only while the tunnel is up, so a stale one never shapes the proxy's rules.
    @Test
    func theNodeIsKeptOnlyWhileTheTunnelIsUp() throws {
        // A suite of its own: the tests run in parallel.
        let suiteName = suiteName + ".node"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TunnelStateStore.record(isUp: true, server: "203.0.113.7", in: defaults, notifying: false)
        #expect(TunnelStateStore.server(in: defaults) == "203.0.113.7")

        TunnelStateStore.record(isUp: false, server: "203.0.113.7", in: defaults, notifying: false)
        #expect(TunnelStateStore.server(in: defaults) == nil)

        TunnelStateStore.record(isUp: true, in: defaults, notifying: false)
        #expect(TunnelStateStore.server(in: defaults) == nil)
    }
}
