//
//  SplitTunnelSettingsTests.swift
//  DVPNCore
//

@testable import DVPNSplitTunnelCore
import Foundation
import Testing

/// Which flows leave the VPN under each mode, and the hand-over between the app and the extension.
///
/// One fixed suite, emptied before and after each test.
@Suite(.serialized)
struct SplitTunnelSettingsTests {
    private let suiteName = "com.example.vpn.tests.split-tunnel"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func disabledKeepsEveryAppInTheVPN() {
        let settings = SplitTunnelSettings(mode: .disabled, apps: ["com.example.a"])

        #expect(!settings.isEnabled)
        #expect(!settings.bypassesVPN("com.example.a"))
        #expect(!settings.bypassesVPN(""))
    }

    @Test
    func exceptSelectedLetsOnlyTheSelectedAppsOut() {
        let settings = SplitTunnelSettings(mode: .exceptSelected, apps: ["com.example.a"])

        #expect(settings.isEnabled)
        #expect(settings.bypassesVPN("com.example.a"))
        #expect(!settings.bypassesVPN("com.example.b"))
        #expect(!settings.bypassesVPN(""))
    }

    @Test
    func allowSelectedKeepsOnlyTheSelectedAppsIn() {
        let settings = SplitTunnelSettings(mode: .allowSelected, apps: ["com.example.a"])

        #expect(!settings.bypassesVPN("com.example.a"))
        #expect(settings.bypassesVPN("com.example.b"))
        #expect(settings.bypassesVPN(""), "a system process is not a selected app")
    }

    @Test
    func savedSettingsAreReadBack() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SplitTunnelSettings(mode: .allowSelected, apps: ["com.example.a", "com.example.b"])

        try SplitTunnelSettingsStore.save(settings, in: defaults)

        #expect(SplitTunnelSettingsStore.load(from: defaults) == settings)
    }

    @Test
    func nothingSavedOrUnreadableReadsAsDisabled() {
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(SplitTunnelSettingsStore.load(from: defaults) == .disabled)

        defaults.set(Data("not json".utf8), forKey: SplitTunnelSettingsStore.key)
        #expect(SplitTunnelSettingsStore.load(from: defaults) == .disabled)
    }
}
