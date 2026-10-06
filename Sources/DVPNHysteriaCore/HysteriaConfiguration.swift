//
//  HysteriaConfiguration.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

// MARK: - HysteriaConfiguration

/// Client configuration for the Hysteria 2 engine.
///
/// This is the JSON contract with `GoBridge/libhysteria` (`LibhysteriaStart(configJSON)`): the
/// Go side decodes exactly these camelCase keys. Keep `GoBridge/libhysteria/config.go` in sync.
public struct HysteriaConfiguration: Codable, Sendable, Equatable {
    public struct TLS: Codable, Sendable, Equatable {
        /// Server name for TLS; defaults to `server` when nil.
        public var sni: String?
        public var insecure: Bool = false
        /// Hex SHA-256 of the server certificate (`:`/`-` separators tolerated).
        public var pinSHA256: String?

        public init(sni: String? = nil, insecure: Bool = false, pinSHA256: String? = nil) {
            self.sni = sni
            self.insecure = insecure
            self.pinSHA256 = pinSHA256
        }
    }

    public struct Obfs: Codable, Sendable, Equatable {
        public static let salamander = "salamander"

        public var type: String = Obfs.salamander
        public var password: String

        public init(type: String = Obfs.salamander, password: String) {
            self.type = type
            self.password = password
        }
    }

    public struct Bandwidth: Codable, Sendable, Equatable {
        public var upMbps: UInt64?
        public var downMbps: UInt64?

        public init(upMbps: UInt64? = nil, downMbps: UInt64? = nil) {
            self.upMbps = upMbps
            self.downMbps = downMbps
        }
    }

    public struct QUIC: Codable, Sendable, Equatable {
        public var initStreamReceiveWindow: UInt64?
        public var maxStreamReceiveWindow: UInt64?
        public var initConnReceiveWindow: UInt64?
        public var maxConnReceiveWindow: UInt64?
        public var maxIdleTimeoutSec: Int?
        public var keepAlivePeriodSec: Int?
        public var disablePathMTUDiscovery: Bool = false

        public init(
            initStreamReceiveWindow: UInt64? = nil,
            maxStreamReceiveWindow: UInt64? = nil,
            initConnReceiveWindow: UInt64? = nil,
            maxConnReceiveWindow: UInt64? = nil,
            maxIdleTimeoutSec: Int? = nil,
            keepAlivePeriodSec: Int? = nil,
            disablePathMTUDiscovery: Bool = false
        ) {
            self.initStreamReceiveWindow = initStreamReceiveWindow
            self.maxStreamReceiveWindow = maxStreamReceiveWindow
            self.initConnReceiveWindow = initConnReceiveWindow
            self.maxConnReceiveWindow = maxConnReceiveWindow
            self.maxIdleTimeoutSec = maxIdleTimeoutSec
            self.keepAlivePeriodSec = keepAlivePeriodSec
            self.disablePathMTUDiscovery = disablePathMTUDiscovery
        }
    }

    public struct SOCKS5: Codable, Sendable, Equatable {
        /// Listen address, e.g. `[::1]:8080` (matches hev-socks5-tunnel's `address: ::1`).
        public var listen: String
        public var udp: Bool = true
        /// When both are set, the SOCKS5 server accepts only these credentials.
        public var username: String?
        public var password: String?

        public init(listen: String, udp: Bool = true, username: String? = nil, password: String? = nil) {
            self.listen = listen
            self.udp = udp
            self.username = username
            self.password = password
        }

        /// A placeholder until the extension starts: the provider replaces it with `local(_:)`.
        public static func loopback(port: Int) -> SOCKS5 {
            SOCKS5(listen: "[::1]:\(port)")
        }

        /// The start's local proxy: its port and credentials.
        public static func local(_ proxy: LocalProxy) -> SOCKS5 {
            SOCKS5(listen: proxy.listenAddress, username: proxy.username, password: proxy.password)
        }
    }

    public var server: String
    public var port: UInt16 = 443
    public var auth: String = ""
    public var tls = TLS()
    public var obfs: Obfs?
    public var bandwidth: Bandwidth?
    public var quic: QUIC?
    public var fastOpen: Bool = true
    public var lazy: Bool = false
    public var socks5: SOCKS5 = .loopback(port: 8080)
    /// Display name (URI fragment); ignored by the Go side.
    public var name: String?

    public init(
        server: String,
        port: UInt16 = 443,
        auth: String = "",
        tls: TLS = TLS(),
        obfs: Obfs? = nil,
        bandwidth: Bandwidth? = nil,
        quic: QUIC? = nil,
        fastOpen: Bool = true,
        lazy: Bool = false,
        socks5: SOCKS5 = .loopback(port: 8080),
        name: String? = nil
    ) {
        self.server = server
        self.port = port
        self.auth = auth
        self.tls = tls
        self.obfs = obfs
        self.bandwidth = bandwidth
        self.quic = quic
        self.fastOpen = fastOpen
        self.lazy = lazy
        self.socks5 = socks5
        self.name = name
    }

    /// The JSON text handed to `LibhysteriaStart`.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
