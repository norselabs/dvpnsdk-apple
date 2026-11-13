//
//  NodeAddressTests.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNSDK
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing

/// The node-address check every start runs: an address as it is, a host name by what it resolves to.
///
/// Every start writes the shared `NodeAddressStore` (App Group defaults), so the suite runs serially.
@MainActor
@Suite(.serialized, .sharesTunnelState)
struct NodeAddressTests {
    private let configuration = DVPNCoreConfiguration(
        appGroupID: "group.com.example.vpn.tests",
        protocols: [
            TunnelProtocolDescriptor(
                id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard",
                readiness: .wireGuardHandshake
            ),
            TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
        ]
    )

    init() {
        DVPNCore.bootstrap(configuration)
    }

    // MARK: The check

    /// A name the system resolves onto this device is refused, as its addresses are when written as literals.
    @Test
    func aNameThatResolvesOntoThisDeviceIsRefused() async throws {
        let addresses = NodeAddress.resolve("localhost")
        try #require(!addresses.isEmpty, "'localhost' resolves to nothing here")
        #expect(addresses.allSatisfy(ConnectionCredentials.isNonPublicAddress))

        let check = await NodeAddress.check("localhost")

        guard case .refused = check else {
            Issue.record("'localhost' was taken: \(check)")
            return
        }
    }

    /// A name resolving to the benchmarking range (the proxy tunnel's own interface address, 198.18.0.1, is in it), or to
    /// a NAT64 or IPv4-compatible address whose IPv4 is not public, is refused; with a public IPv4 inside, it passes.
    @Test(arguments: [
        ("198.18.0.1", true), ("198.19.255.255", true), ("198.20.0.1", false),
        ("64:ff9b::c0a8:101", true), ("64:ff9b::a00:1", true), ("64:ff9b::cb00:710a", false),
        ("::c0a8:101", true), ("::7f00:1", true), ("::cb00:710a", false),
    ])
    func theBenchmarkingNAT64AndIPv4CompatibleRanges(answer: String, isRefused: Bool) async {
        let check = await NodeAddress.check("node.example.com") { _ in [answer] }

        #expect(check == (isRefused ? .refused(answer) : .addresses([answer])))
    }

    /// One non-public address among public ones is enough to refuse a name.
    @Test(arguments: ["192.168.1.20", "10.0.0.5", "127.0.0.1", "fe80::1%en0", "::1", "::ffff:203.0.113.5"])
    func aNameWithOneNonPublicAddressIsRefused(nonPublic: String) async {
        let check = await NodeAddress.check("node.example.com") { _ in ["203.0.113.10", nonPublic] }

        #expect(check == .refused(nonPublic))
    }

    @Test
    func aNameWithOnlyPublicAddressesKeepsThemInOrder() async {
        let check = await NodeAddress.check("node.example.com") { _ in ["203.0.113.10", "2001:db8::10"] }

        #expect(check == .addresses(["203.0.113.10", "2001:db8::10"]))
    }

    /// A name that resolves to nothing is left to the engine's own lookup.
    @Test
    func aNameThatResolvesToNothingPasses() async throws {
        #expect(await NodeAddress.check("node.example.com") { _ in [] } == .unresolved)
        try await NodeAddress.refuseNonPublic("node.example.com") { _ in [] }
    }

    /// An address is checked as it is, with no lookup.
    @Test
    func anAddressIsCheckedWithoutALookup() async {
        let lookups = LockedCount()
        let resolve: @Sendable (String) -> [String] = { _ in lookups.add(); return [] }

        #expect(await NodeAddress.check("203.0.113.10", resolve: resolve) == .addresses(["203.0.113.10"]))
        #expect(await NodeAddress.check("192.168.1.1", resolve: resolve) == .refused("192.168.1.1"))
        #expect(lookups.value == 0)
    }

    /// What a packet tunnel provider runs on every start the system makes: it throws for a non-public node.
    @Test
    func theProvidersCheckThrowsForANonPublicNode() async {
        await #expect(throws: (any Error).self) {
            try await NodeAddress.refuseNonPublic("node.example.com") { _ in ["192.168.1.20"] }
        }
        await #expect(throws: Never.self) {
            try await NodeAddress.refuseNonPublic("node.example.com") { _ in ["203.0.113.10"] }
        }
    }

    // MARK: What a proxy engine records

    /// A proxy engine records a name as every address it resolved to, so the split-tunnel proxy leaves out whichever of
    /// them the engine dials, with no lookup of its own.
    @Test
    func aProxyRecordsANamesAddresses() async throws {
        let recorded = try await NodeAddress.recordedNode("node.example.com") { _ in ["203.0.113.10", "2001:db8::10"] }

        #expect(recorded == "203.0.113.10,2001:db8::10")
    }

    /// An address is recorded as it is; a name that resolves to nothing is recorded as the name.
    @Test
    func anAddressOrAnUnresolvedNameIsRecordedAsWritten() async throws {
        #expect(try await NodeAddress.recordedNode("203.0.113.10") { _ in [] } == "203.0.113.10")
        #expect(try await NodeAddress.recordedNode("node.example.com") { _ in [] } == "node.example.com")
    }

    @Test
    func aNonPublicNodeIsNotRecorded() async {
        await #expect(throws: (any Error).self) {
            _ = try await NodeAddress.recordedNode("node.example.com") { _ in ["192.168.1.20"] }
        }
    }

    // MARK: The ranges

    /// The tunnel layer's ranges and the decoder's are the same, address by address. The decoder's live in DVPNSDK,
    /// which the extensions may not link.
    @Test(arguments: [
        "0.0.0.1", "10.1.2.3", "100.64.0.1", "100.127.255.255", "100.128.0.1", "127.0.0.1", "169.254.1.1", "172.16.0.1",
        "172.31.255.255", "172.32.0.1", "192.168.0.1", "192.169.0.1", "224.0.0.1", "240.0.0.1", "255.255.255.255",
        "203.0.113.5", "1.1.1.1", "::", "::1", "::2", "fc00::1", "fdff::1", "fe80::1", "febf::1", "fec0::1", "ff02::1",
        "::ffff:203.0.113.5", "2001:db8::1", "2606:4700::1111",
        "198.17.255.255", "198.18.0.0", "198.18.0.1", "198.19.255.255", "198.20.0.1",
        "64:ff9b::a00:1", "64:ff9b::c0a8:101", "64:ff9b::cb00:710a", "64:ff9a::a00:1",
        "::a00:1", "::c0a8:101", "::cb00:710a", "::7f00:1",
    ])
    func theRangesMatchTheDecoders(address: String) {
        #expect(NodeAddress.isNonPublic(address) == ConnectionCredentials.isNonPublicAddress(address))
    }

    /// A resolver answer that cannot be written as an address refuses the name.
    @Test
    func anUnwrittenAnswerRefusesTheName() async {
        #expect(await NodeAddress.check("node.example.com") { _ in ["203.0.113.10", ""] } == .refused(""))
    }

    /// What is not an address counts as not public: a resolver answer the check cannot read never passes.
    @Test(arguments: ["", "not-an-address", "fe80::zz"])
    func whatIsNotAnAddressIsNotPublic(text: String) {
        #expect(NodeAddress.isNonPublic(text))
    }

    // MARK: The start

    /// `start(from:)` refuses a node given as a name that resolves onto this device, before anything dials it.
    @Test
    func aStartRefusesANameThatResolvesOntoThisDevice() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeAddressStore.record(nil)
        }
        try await TunnelConfigDirectories.$homeDirectoryOverride.withValue(directory) {
            let profile = FakeTunnelProfile(name: "Xray", providerBundleID: "com.example.vpn.v2ray-ne")
            let store = FakeTunnelProfileStore()
            store.profiles = [profile]
            let service = TunnelsService(tunnelProviders: [profile], store: store, clock: StepClock())
            profile.onStatusChange = { [weak service] in service?.profileStatusDidChange($0) }
            let manager = TunnelManager(settings: FakeTunnelSettings(), configuration: configuration)
            manager.attach(service)
            let credentials = ConnectionCredentials(
                nodeType: .v2ray,
                endpoint: .v2ray(V2RayNodeEndpoint(
                    host: "localhost", inbounds: [V2RayInbound(port: 8443, proxyProtocol: .vmess, transport: .grpc)]
                )),
                uid: "11111111-2222-3333-4444-555555555555"
            )

            await #expect(throws: TunnelsServiceError.refusedNodeAddress) { try await manager.start(from: credentials) }
            #expect(profile.starts == 0, "the node was dialled")
        }
    }
}

/// A count a `@Sendable` closure can add to. `@unchecked`: every access to `count` goes through the lock.
private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func add() { lock.withLock { count += 1 } }
}
