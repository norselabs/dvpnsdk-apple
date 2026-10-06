//
//  XrayInvokeSmokeTests.swift
//  DVPNCore
//

@testable import DVPNXRayProvider
import Foundation
import Testing

/// LibXray validates one configuration at a time (`testXray` refuses a second instance), so every
/// suite that calls it nests here and runs serialized.
@Suite(.serialized)
enum LibXrayTests {}

extension LibXrayTests {
    /// Proves the Go c-archive links into the test bundle and the Invoke envelope round-trips.
    @Suite(.serialized)
    struct XrayInvokeSmokeTests {
        @Test
        func versionIsReported() throws {
            let version = try XrayInvoke.xrayVersion()
            #expect(!version.isEmpty)
            #expect(version != "unknown")
        }

        @Test
        func notRunningByDefault() {
            #expect(!XrayInvoke.isRunning())
        }

        @Test
        func xrayRejectsGarbage() {
            #expect(throws: (any Error).self) { try XrayInvoke.testXray(configJSON: "{\"outbounds\":[{\"protocol\":\"nope\"}]}") }
        }

        @Test
        func xrayAcceptsMinimalConfig() throws {
            try XrayInvoke.testXray(configJSON: "{\"outbounds\":[{\"protocol\":\"freedom\",\"tag\":\"direct\"}]}")
        }
    }
}
