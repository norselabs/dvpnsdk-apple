//
//  LocalProxyTests.swift
//  DVPNCore
//

import Darwin
import DVPNCoreKit
import Testing

/// Every tunnel start gets its own local SOCKS5 proxy, so other processes can neither use it nor find it on a
/// fixed port.
struct LocalProxyTests {
    @Test
    func eachStartGetsAFreePortAndNewCredentials() throws {
        let first = try LocalProxy.random()
        let second = try LocalProxy.random()

        #expect((1024 ... 65_535).contains(first.port))
        #expect(first.username != second.username)
        #expect(first.password != second.password)
        #expect(first.username != first.password)
        for token in [first.username, first.password] {
            #expect(token.count == 32)
            #expect(token.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
        #expect(try canListen(on: first.port))
    }

    @Test
    func theListenAddressIsTheIPv6Loopback() {
        #expect(LocalProxy.fixture.listenAddress == "[::1]:8080")
    }

    /// The engine must be able to bind the port it is given.
    private func canListen(on port: Int) throws -> Bool {
        let descriptor = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_addr = in6addr_loopback
        address.sin6_port = UInt16(port).bigEndian
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }
}
