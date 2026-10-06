//
//  LocalProxy.swift
//  DVPNCore
//

import Darwin
import Foundation

// MARK: - LocalProxy

/// The SOCKS5 proxy on the loopback interface between hev-socks5-tunnel and a proxy engine (Xray, Hysteria).
///
/// Every tunnel start makes a new one: a free port and random credentials. Any process on the device can
/// reach a loopback port, so a fixed port without a password let other apps use the VPN or detect it.
public struct LocalProxy: Equatable, Sendable {
    /// Always the IPv6 loopback address, as both engines and hev-socks5-tunnel are configured.
    public static let host = "::1"

    public let port: Int
    public let username: String
    public let password: String

    public init(port: Int, username: String, password: String) {
        self.port = port
        self.username = username
        self.password = password
    }

    /// `[::1]:<port>`, the listen address the engines take.
    public var listenAddress: String { "[\(Self.host)]:\(port)" }

    /// A free loopback port, found by binding port 0, and credentials of 32 random hex characters each
    /// (no characters that need quoting in YAML or JSON).
    public static func random() throws -> LocalProxy {
        LocalProxy(port: try freeLoopbackPort(), username: randomToken(), password: randomToken())
    }
}

// MARK: - Private

private extension LocalProxy {
    static func randomToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// The port the system picks for `[::1]:0`. The socket closes before the engine binds the port; another
    /// process taking it in between only fails this start.
    static func freeLoopbackPort() throws -> Int {
        let socketDescriptor = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        guard socketDescriptor >= 0 else { throw NSError.newError("No socket for a local proxy port (errno \(errno))") }
        defer { close(socketDescriptor) }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_addr = in6addr_loopback
        address.sin6_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                bind(socketDescriptor, address, length) == 0 && getsockname(socketDescriptor, address, &length) == 0
            }
        }
        guard bound else { throw NSError.newError("No free local proxy port (errno \(errno))") }
        return Int(UInt16(bigEndian: address.sin6_port))
    }
}
