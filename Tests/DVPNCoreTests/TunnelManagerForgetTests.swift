//
//  TunnelManagerForgetTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing
import WireGuardKitTypes

/// `TunnelManager.forgetStoredConfiguration()`: what a start of each engine leaves in the App Group, and what is left
/// after a forget. The configuration directories are excluded from device backups.
///
/// Every start writes the shared `NodeAddressStore` (App Group defaults), so the suite runs serially.
///
/// The descriptors match the other suites': `DVPNCore.bootstrap` writes a process-global one, and the suites run
/// beside each other in one process.
@MainActor
@Suite(.serialized, .sharesTunnelState)
struct TunnelManagerForgetTests {
    private let configuration = DVPNCoreConfiguration(
        appGroupID: "group.com.example.vpn.tests",
        protocols: [
            TunnelProtocolDescriptor(
                id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard",
                readiness: .wireGuardHandshake
            ),
            TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
            TunnelProtocolDescriptor(
                id: .hysteria, providerBundleID: "com.example.vpn.hysteria-ne", tunnelName: "Hysteria", readiness: .immediate
            ),
        ]
    )

    init() {
        DVPNCore.bootstrap(configuration)
    }

    /// A start of each engine writes its configuration; one forget takes all three, with the directories holding them.
    @Test
    func aForgetTakesEveryEnginesStoredConfiguration() async throws {
        try await withConfigurationFilesOfItsOwn { home in
            let manager = makeManager()
            try await startEveryEngine(with: manager)

            let files = Self.configurationFiles(under: home)
            #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })

            manager.forgetStoredConfiguration()

            for file in files {
                #expect(
                    !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
                    "\(file.lastPathComponent) under \(file.deletingLastPathComponent().lastPathComponent) is still stored"
                )
                let folder = file.deletingLastPathComponent()
                #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
            }
        }
    }

    /// A forget leaves nothing for a restart to start from, whichever engine ran last: each reads its own store
    /// (WireGuard's through the profile, the proxy engines' straight from the App Group).
    @Test(arguments: TunnelProtocolID.allCases)
    func aRestartAfterAForgetHasNothingToStartFrom(lastEngine: TunnelProtocolID) async throws {
        try await withConfigurationFilesOfItsOwn { _ in
            let manager = makeManager()
            try await startEveryEngine(with: manager)
            try await start(lastEngine, with: manager)

            manager.forgetStoredConfiguration()

            await #expect(throws: TunnelsServiceError.noStoredConfiguration) { try await manager.restart() }
        }
    }

    /// After a forget, the next process's service keeps the profile, whichever engine it was last, with on-demand off:
    /// the system no longer starts a tunnel that has nothing to start from, and the profile is not removed.
    @Test(arguments: TunnelProtocolID.allCases)
    func theNextLaunchKeepsTheProfileWithOnDemandOff(lastEngine: TunnelProtocolID) async throws {
        try await withConfigurationFilesOfItsOwn { _ in
            let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
            let (manager, store) = makeManager(over: profile)
            try await start(lastEngine, with: manager)
            #expect(profile.isOnDemandEnabled)
            let saves = profile.saves

            manager.forgetStoredConfiguration()
            let service = try await TunnelsService.create(store: store, clock: StepClock())

            #expect(profile.removals == 0, "the profile was removed")
            #expect(!profile.isOnDemandEnabled, "on-demand is still on, with nothing to start from")
            #expect(profile.saves == saves + 1, "on-demand was turned off but not saved")
            #expect(service.tunnels.count == 1)
        }
    }

    /// A profile whose configuration is still stored keeps on-demand as it was.
    @Test(arguments: TunnelProtocolID.allCases)
    func theNextLaunchLeavesAConfiguredProfileAlone(lastEngine: TunnelProtocolID) async throws {
        try await withConfigurationFilesOfItsOwn { _ in
            let profile = FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")
            let (manager, store) = makeManager(over: profile)
            try await start(lastEngine, with: manager)
            let saves = profile.saves

            _ = try await TunnelsService.create(store: store, clock: StepClock())

            #expect(profile.isOnDemandEnabled)
            #expect(profile.saves == saves)
            #expect(profile.removals == 0)
        }
    }

    /// A forget with nothing stored is no error, and a start after it stores again.
    @Test
    func aForgetWithNothingStoredIsNoError() async throws {
        try await withConfigurationFilesOfItsOwn { home in
            let manager = makeManager()

            manager.forgetStoredConfiguration()
            try await startEveryEngine(with: manager)

            let files = Self.configurationFiles(under: home)
            #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
        }
    }

    /// The root of the configuration files carries the backup exclusion, so every engine's directory under it reads
    /// as excluded too. Only the root carries the flag itself: the engines make their `*_CURRENT` directories with
    /// `FileManager` and inherit the root's.
    @Test
    func theConfigurationRootIsExcludedFromBackups() async throws {
        try await withConfigurationFilesOfItsOwn { home in
            let manager = makeManager()
            try await startEveryEngine(with: manager)

            let directories = [home] + Self.configurationFiles(under: home).map { $0.deletingLastPathComponent() }
            for directory in directories {
                let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
                #expect(values.isExcludedFromBackup == true, "\(directory.lastPathComponent) is in the backup")
            }
        }
    }

    // MARK: Fixtures

    /// Where each engine's start leaves its configuration.
    private static func configurationFiles(under home: URL) -> [URL] {
        [
            home.appending(components: "wireguard", TunnelConfigDirectories.wireguardCurrentConfigKey, "config.json"),
            home.appending(components: "configs", TunnelConfigDirectories.xrayCurrentConfigKey, "config.json"),
            home.appending(components: "hysteria", TunnelConfigDirectories.hysteriaCurrentConfigKey, "config.json"),
        ]
    }

    /// One start per engine, each rewriting the one profile, as a user switching protocols makes them.
    private func startEveryEngine(with manager: TunnelManager) async throws {
        for engine in TunnelProtocolID.allCases {
            try await start(engine, with: manager)
        }
    }

    private func start(_ engine: TunnelProtocolID, with manager: TunnelManager) async throws {
        let key = "WAmgVYXkbT2bCtdcDwolI88/iqlDu4tf4B9Bl6qaJ0U="
        let uid = "11111111-2222-3333-4444-555555555555"
        let credentials = switch engine {
        case .wireGuard:
            ConnectionCredentials(
                nodeType: .wireguard,
                endpoint: .wireGuard(WireGuardEndpoint(
                    host: "203.0.113.10", port: 51820, clientAddress: "10.10.0.2",
                    peerPublicKey: "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
                )),
                privateKey: key
            )
        case .xray:
            ConnectionCredentials(
                nodeType: .v2ray,
                endpoint: .v2ray(V2RayNodeEndpoint(
                    host: "203.0.113.20", inbounds: [V2RayInbound(port: 8443, proxyProtocol: .vmess, transport: .grpc)]
                )),
                uid: uid
            )
        case .hysteria:
            ConnectionCredentials(
                nodeType: .hysteria,
                endpoint: .hysteria(HysteriaEndpoint(host: "203.0.113.30", port: 443)),
                uid: uid
            )
        }
        try await manager.start(from: credentials)
    }

    private func withConfigurationFilesOfItsOwn(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeAddressStore.record(nil)
        }
        try await TunnelConfigDirectories.$homeDirectoryOverride.withValue(directory) {
            try await body(directory)
        }
    }

    /// A manager over a service of one fake profile, which every engine rewrites.
    private func makeManager() -> TunnelManager {
        makeManager(over: FakeTunnelProfile(name: "WireGuard", providerBundleID: "com.example.vpn.wireguard-ne")).manager
    }

    private func makeManager(over profile: FakeTunnelProfile) -> (manager: TunnelManager, store: FakeTunnelProfileStore) {
        let store = FakeTunnelProfileStore()
        store.profiles = [profile]
        let service = TunnelsService(tunnelProviders: [profile], store: store, clock: StepClock())
        profile.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) }
        store.onMake = { [weak service] made in
            made.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) }
        }
        let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: configuration)
        manager.attach(service)
        return (manager, store)
    }
}
