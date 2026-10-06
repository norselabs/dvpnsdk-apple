//
//  ProxyStartErrorStoreTests.swift
//  DVPNCore
//

@testable import DVPNCoreKit
import Foundation
import Testing

/// The proxy extensions leave why they failed to start for the app's log.
struct ProxyStartErrorStoreTests {
    /// One fixed suite, so a run leaves no new preferences file behind.
    private let suiteName = "com.example.vpn.tests.proxy-start-error"

    @Test
    func aRecordedReasonIsReadBackUntilCleared() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ProxyStartErrorStore.load(from: defaults) == nil)

        ProxyStartErrorStore.record("Hysteria start failed: authentication error", in: defaults)
        #expect(ProxyStartErrorStore.load(from: defaults)?.message == "Hysteria start failed: authentication error")

        ProxyStartErrorStore.clear(in: defaults)
        #expect(ProxyStartErrorStore.load(from: defaults) == nil)
    }
}
