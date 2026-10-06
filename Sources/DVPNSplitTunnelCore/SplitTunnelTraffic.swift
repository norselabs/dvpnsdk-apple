//
//  SplitTunnelTraffic.swift
//  DVPNCore
//

import Foundation

// MARK: - SplitTunnelTraffic

/// What the split-tunnel proxy is offered and what it never sees. The provider turns
/// these into `NENetworkRule`s; they live here, without NetworkExtension, so the tests can read them.
public enum SplitTunnelTraffic {
    /// A destination: an address and a prefix length, optionally one port and UDP only.
    public struct Destination: Equatable, Sendable {
        public let address: String
        public let prefix: Int
        public let port: UInt16?
        public let isUDPOnly: Bool

        init(_ address: String, _ prefix: Int, port: UInt16? = nil, udpOnly: Bool = false) {
            self.address = address
            self.prefix = prefix
            self.port = port
            isUDPOnly = udpOnly
        }
    }

    /// Every outbound flow of either family. A wildcard address must name a port, so each rule names a real address
    /// with a zero-length prefix, which matches any address of that family.
    public static let offered: [Destination] = [
        Destination("1.0.0.0", 0),
        Destination("2000::", 0),
    ]

    /// Left out of the proxy, whatever the app: the system's DHCP, whose renewals share one socket that a proxy
    /// which stops or dies would take down with it, and traffic that stays on the local network or the
    /// machine, which needs no split. Rules that name a wildcard address name a port.
    public static let excluded: [Destination] = [
        // DHCP and DHCPv6.
        Destination("0.0.0.0", 0, port: 67, udpOnly: true),
        Destination("0.0.0.0", 0, port: 68, udpOnly: true),
        Destination("::", 0, port: 546, udpOnly: true),
        Destination("::", 0, port: 547, udpOnly: true),
        // Private, link-local, loopback, multicast and broadcast addresses.
        Destination("10.0.0.0", 8),
        Destination("172.16.0.0", 12),
        Destination("192.168.0.0", 16),
        Destination("169.254.0.0", 16),
        Destination("127.0.0.0", 8),
        Destination("224.0.0.0", 4),
        Destination("255.255.255.255", 32),
        Destination("fc00::", 7),
        Destination("fe80::", 10),
        Destination("ff00::", 8),
        Destination("::1", 128),
    ]
}

// MARK: - SplitTunnelMessage

/// What the app tells a running proxy, instead of restarting it.
public enum SplitTunnelMessage: UInt8, Sendable {
    /// The settings changed in the App Group: read them again.
    case reloadSettings = 1

    public var data: Data { Data([rawValue]) }

    public init?(data: Data) {
        guard data.count == 1, let message = Self(rawValue: data[0]) else { return nil }
        self = message
    }
}
