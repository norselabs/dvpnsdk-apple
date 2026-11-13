//
//  NodeAddress.swift
//  DVPNSDK
//

import Foundation
import Network

// MARK: - NodeAddress

/// Where a node's host leads. Every start checks it: `TunnelManager.start(from:)`, and each packet tunnel provider
/// when the system starts it, so a restart and an on-demand start are checked too.
///
/// A host name is resolved once, here, and refused when any address it resolves to is not public. The engine is
/// still given the name and looks it up again when it dials, so a resolver that answers differently the second time
/// is not caught. A name that resolves to nothing is not refused: the engine's own lookup decides.
package enum NodeAddress {
    /// What the check found.
    package enum Check: Equatable, Sendable {
        /// The host's public addresses: itself when it is an address, else what the name resolved to, in the
        /// resolver's order.
        case addresses([String])
        /// A name that resolved to nothing.
        case unresolved
        /// The first address that is not public, which the host is refused for.
        case refused(String)
    }

    /// Checks `host`: an address as it is, a name by what `resolve` returns for it. Runs on the concurrent executor,
    /// never the caller's actor, since the system's resolver blocks while it looks the name up.
    @concurrent
    package static func check(
        _ host: String,
        resolve: @Sendable (String) -> [String] = NodeAddress.resolve
    ) async -> Check {
        if isAddress(host) {
            return isNonPublic(host) ? .refused(host) : .addresses([host])
        }
        let addresses = resolve(host)
        guard !addresses.isEmpty else { return .unresolved }
        if let refused = addresses.first(where: isNonPublic) { return .refused(refused) }
        return .addresses(addresses)
    }

    /// Throws when `host` is, or resolves to, an address that is not public; the error names both. What a packet
    /// tunnel provider runs before its tunnel's settings.
    package static func refuseNonPublic(
        _ host: String,
        resolve: @Sendable (String) -> [String] = NodeAddress.resolve
    ) async throws {
        guard case let .refused(address) = await check(host, resolve: resolve) else { return }
        throw NSError.newError(
            "Refused the node \(host.escapingControlCharacters): it resolves to \(address), not a public address"
        )
    }

    /// `host`'s addresses through the system's resolver, numeric, each once, in the resolver's order; empty when it
    /// does not resolve. Blocks while the resolver runs.
    package static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
            ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        for info in sequence(first: first, next: { $0.pointee.ai_next }) {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            let address = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            if !addresses.contains(address) { addresses.append(address) }
        }
        return addresses
    }

    /// Whether `address` is not public: this device, a private or shared network, a link, multicast, or a reserved or
    /// IPv4-mapped range — the ranges `ConnectionCredentials.isNonPublicAddress` refuses. A scoped IPv6 address
    /// (`fe80::1%en0`) is read without its scope, and anything that is not an address counts as not public.
    package static func isNonPublic(_ address: String) -> Bool {
        let unscoped = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        if let address = IPv4Address(unscoped) {
            let bytes = [UInt8](address.rawValue)
            switch (bytes[0], bytes[1]) {
            case (0, _), (10, _), (127, _), (169, 254), (192, 168), (224..., _): return true // 224/4 and 240/4
            case (100, 64 ... 127), (172, 16 ... 31): return true
            default: return false
            }
        }
        if let address = IPv6Address(unscoped) {
            let bytes = [UInt8](address.rawValue)
            let isUnspecifiedOrLoopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] <= 1
            return isUnspecifiedOrLoopback || address.isIPv4Mapped
                || bytes[0] & 0xFE == 0xFC // fc00::/7
                || (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80) // fe80::/10
                || bytes[0] == 0xFF // ff00::/8
        }
        return true
    }

    /// Whether `host` is an IPv4 or IPv6 address rather than a name.
    private static func isAddress(_ host: String) -> Bool {
        IPv4Address(host) != nil || IPv6Address(host) != nil
    }
}
