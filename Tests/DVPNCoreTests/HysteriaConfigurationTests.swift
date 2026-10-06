//
//  HysteriaConfigurationTests.swift
//  DVPNCore
//

import DVPNCoreKit
@testable import DVPNHysteriaCore
import Foundation
import Testing

struct HysteriaConfigurationTests {
    @Test
    func fixtureIsTheGoContract() throws {
        // The same document lives in GoBridge/libhysteria/testdata/config.json; both sides must accept it.
        let url = try #require(Bundle.module.url(forResource: "hysteria-config", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(HysteriaConfiguration.self, from: data)

        #expect(configuration.server == "203.0.113.10")
        #expect(configuration.bandwidth == .init(upMbps: 20, downMbps: 100))
        #expect(configuration.quic?.maxIdleTimeoutSec == 30)
        #expect(configuration.socks5 == .init(listen: "[::1]:8080", username: "local-user", password: "local-pass"))

        let canonicalFixture = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
        let rendered = try JSONSerialization.jsonObject(with: Data(configuration.jsonString().utf8))
        let reencoded = try JSONSerialization.data(withJSONObject: rendered, options: [.sortedKeys])
        #expect(String(decoding: reencoded, as: UTF8.self) == String(decoding: canonicalFixture, as: UTF8.self))
    }

    /// The extension's start replaces the stored SOCKS5 section with its local proxy.
    @Test
    func theLocalProxyGivesTheListenAddressAndCredentials() {
        let proxy = LocalProxy(port: 49_152, username: "user", password: "pass")
        #expect(HysteriaConfiguration.SOCKS5.local(proxy) == .init(listen: "[::1]:49152", username: "user", password: "pass"))
    }
}
