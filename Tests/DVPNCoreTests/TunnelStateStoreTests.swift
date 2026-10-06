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
}
