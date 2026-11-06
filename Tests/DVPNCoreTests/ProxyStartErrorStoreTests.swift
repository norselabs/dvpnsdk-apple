//
//  ProxyStartErrorStoreTests.swift
//  DVPNSDK
//

@testable import DVPNCoreKit
import Foundation
import Testing

/// The proxy extensions leave why they failed to start for the app's log. The tests share one defaults suite, so they
/// run one after the other.
@Suite(.serialized)
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

    /// Xray-core quotes a malformed value whole in its error: a line break a node put in it stays on the error's line.
    @Test
    func aRecordedReasonStaysOnOneLine() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ProxyStartErrorStore.record("invalid \"password\": abc\r\n2026-11-06 forged\u{2028}line\u{1B}[0m", in: defaults)
        #expect(ProxyStartErrorStore.load(from: defaults)?.message == #"invalid "password": abc\r\n2026-11-06 forged\u{2028}line\u{1B}[0m"#)
    }
}
