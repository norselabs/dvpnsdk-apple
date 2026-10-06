//
//  StreamSettings.swift
//  DVPNCore
//

import Foundation

// MARK: - StreamSettings

public struct StreamSettings: Codable, Sendable, Equatable {
    // MARK: - TLS

    /// Xray-core 26.x removed `allowInsecure`; certificate trust is expressed either by a valid
    /// chain for `serverName`, by pinning (`pinnedPeerCertSha256`, hex SHA-256 of the leaf certificate) or by
    /// verifying the chain against another name (`verifyPeerCertByName`).
    public struct TLS: Codable, Sendable, Equatable {
        public var serverName: String = ""
        public var alpn: [ALPN] = ALPN.allCases
        public var fingerprint: Fingerprint = .chrome
        public var pinnedPeerCertSha256: String?
        public var verifyPeerCertByName: String?

        public init(
            serverName: String = "",
            alpn: [ALPN] = ALPN.allCases,
            fingerprint: Fingerprint = .chrome,
            pinnedPeerCertSha256: String? = nil,
            verifyPeerCertByName: String? = nil
        ) {
            self.serverName = serverName
            self.alpn = alpn
            self.fingerprint = fingerprint
            self.pinnedPeerCertSha256 = pinnedPeerCertSha256
            self.verifyPeerCertByName = verifyPeerCertByName
        }
    }

    // MARK: - Reality

    public struct Reality: Codable, Sendable, Equatable {
        public var show: Bool = false
        public var fingerprint: Fingerprint = .chrome
        public var serverName: String = ""
        public var publicKey: String = ""
        public var shortId: String = ""
        public var spiderX: String = ""

        public init(
            show: Bool = false,
            fingerprint: Fingerprint = .chrome,
            serverName: String = "",
            publicKey: String = "",
            shortId: String = "",
            spiderX: String = ""
        ) {
            self.show = show
            self.fingerprint = fingerprint
            self.serverName = serverName
            self.publicKey = publicKey
            self.shortId = shortId
            self.spiderX = spiderX
        }
    }

    // MARK: - TCP

    public struct TCP: Codable, Sendable, Equatable {
        public struct Header: Codable, Sendable, Equatable {
            public var type: XHeaderType = .none

            public init(type: XHeaderType = .none) {
                self.type = type
            }
        }

        public var header = Header()

        public init(header: Header = Header()) {
            self.header = header
        }
    }

    // MARK: - WebSocket

    public struct WebSocket: Codable, Sendable, Equatable {
        public var path: String = "/"
        public var headers: [String: String] = [:]

        public init(path: String = "/", headers: [String: String] = [:]) {
            self.path = path
            self.headers = headers
        }
    }

    // MARK: - GRPC

    public struct GRPC: Codable, Sendable, Equatable {
        public var serviceName: String = ""
        public var multiMode: Bool = false

        public init(serviceName: String = "", multiMode: Bool = false) {
            self.serviceName = serviceName
            self.multiMode = multiMode
        }
    }

    // MARK: - XHTTP

    /// XHTTP (SplitHTTP successor) transport settings.
    public struct XHTTP: Codable, Sendable, Equatable {
        public enum Mode: String, Identifiable, CaseIterable, Codable, Sendable {
            public var id: Self { self }

            case auto
            case packetUp = "packet-up"
            case streamUp = "stream-up"
            case streamOne = "stream-one"
        }

        public var host: String = ""
        public var path: String = "/"
        public var mode: Mode = .auto

        public init(host: String = "", path: String = "/", mode: Mode = .auto) {
            self.host = host
            self.path = path
            self.mode = mode
        }
    }

    // MARK: - HTTPUpgrade

    public struct HTTPUpgrade: Codable, Sendable, Equatable {
        public var host: String = ""
        public var path: String = "/"

        public init(host: String = "", path: String = "/") {
            self.host = host
            self.path = path
        }
    }
}
