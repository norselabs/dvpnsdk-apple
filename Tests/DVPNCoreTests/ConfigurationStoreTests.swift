//
//  ConfigurationStoreTests.swift
//  DVPNSDK
//

import DVPNCoreKit
@testable import DVPNHysteriaCore
import Foundation
import Testing

extension ConfigurationFileSuites {
    /// The configuration files the app writes for its extensions, kept in a temporary directory
    /// (`TunnelConfigDirectories.overrideHomeDirectory(_:)`).
    @Suite(.serialized)
    struct ConfigurationStoreTests {
        init() {
            TemporaryConfigDirectory.use()
        }

        @Test
        func theOverrideHoldsTheFiles() throws {
            let home = try #require(TunnelConfigDirectories.homeDirectory)

            #expect(home.standardizedFileURL == TemporaryConfigDirectory.url.standardizedFileURL)
            #expect(FileManager.default.fileExists(atPath: home.path(percentEncoded: false)))
        }

        @Test
        func aStoredHysteriaConfigurationIsReadBack() throws {
            let configuration = HysteriaConfiguration(
                server: "203.0.113.6", port: 17435, auth: "client", tls: .init(insecure: true, pinSHA256: "ab")
            )

            try HysteriaConfigurationStore.save(configuration)

            #expect(try HysteriaConfigurationStore.loadCurrent() == configuration)
        }
    }
}
