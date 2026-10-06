//
//  TLSLeafProbe.swift
//  DVPNCore
//

import CryptoKit
import Foundation
import Network
import os
import Security

// MARK: - CertificatePin

enum CertificatePin {
    /// Lowercase hex SHA-256 of a certificate's DER bytes: the format of Xray's `pinnedPeerCertSha256`
    /// (`sha256.Sum256(cert.Raw)` in Xray-core) and of `openssl x509 -outform DER | shasum -a 256`.
    static func sha256Hex(der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - TLSLeafProbe

/// One TLS handshake with a node, accepting any certificate, that reports the pin of the leaf certificate
/// the node presented. Runs inside the tunnel extension right before Xray-core dials the same node, and
/// mirrors what Xray's outbound sends (SNI, ALPN h2 + http/1.1, TLS 1.2+) so a server that serves several
/// certificates presents the same one to both.
public enum TLSLeafProbe {
    public enum Error: LocalizedError, Equatable, Sendable {
        case invalidPort(host: String, port: Int)
        case timedOut(host: String, port: Int)
        case failed(host: String, port: Int, reason: String)
        case noCertificate(host: String, port: Int)

        public var errorDescription: String? {
            switch self {
            case let .invalidPort(host, port):
                return "TLS probe of \(host):\(port): invalid port"
            case let .timedOut(host, port):
                return "TLS probe of \(host):\(port) timed out"
            case let .failed(host, port, reason):
                return "TLS probe of \(host):\(port) failed: \(reason)"
            case let .noCertificate(host, port):
                return "TLS probe of \(host):\(port): the server presented no certificate"
            }
        }
    }

    /// Handshakes with `host:port` and returns the SHA-256 pin of the presented leaf certificate.
    /// - Parameters:
    ///   - serverName: SNI to send when it is a host name; IP literals and empty strings send no SNI, like Xray.
    ///   - timeout: Overall deadline for connect + handshake.
    public static func observeLeafSHA256(
        host: String,
        port: Int,
        serverName: String? = nil,
        timeout: TimeInterval = 3
    ) async throws -> String {
        guard (1 ... 65535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw Error.invalidPort(host: host, port: port)
        }

        let tlsOptions = NWProtocolTLS.Options()
        let securityOptions = tlsOptions.securityProtocolOptions
        if let serverName, !serverName.isEmpty, !isIPLiteral(serverName) {
            serverName.withCString { sec_protocol_options_set_tls_server_name(securityOptions, $0) }
        }
        for alpn in ["h2", "http/1.1"] {
            alpn.withCString { sec_protocol_options_add_tls_application_protocol(securityOptions, $0) }
        }
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv12)

        let observedLeaf = OSAllocatedUnfairLock<String?>(initialState: nil)
        sec_protocol_options_set_verify_block(securityOptions, { _, trustRef, complete in
            let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first {
                let pin = CertificatePin.sha256Hex(der: SecCertificateCopyData(leaf) as Data)
                observedLeaf.withLock { $0 = pin }
            }
            complete(true)
        }, DispatchQueue(label: "io.norselabs.dvpn.tls-leaf-probe.verify"))

        let parameters = NWParameters(tls: tlsOptions)
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = Int(timeout.rounded(.up))
            tcp.noDelay = true
        }

        let session = Session(connection: NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters))
        return try await withCheckedThrowingContinuation { continuation in
            session.begin(continuation: continuation, host: host, port: port, observedLeaf: observedLeaf, timeout: timeout)
        }
    }

    static func isIPLiteral(_ name: String) -> Bool {
        IPv4Address(name) != nil || IPv6Address(name) != nil
    }
}

// MARK: - Session

private extension TLSLeafProbe {
    /// Owns the connection for one probe and resumes the continuation exactly once.
    /// `@unchecked`: the continuation is handed over under the lock; the connection and queue are immutable.
    final class Session: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, any Swift.Error>?
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "io.norselabs.dvpn.tls-leaf-probe")

        init(connection: NWConnection) {
            self.connection = connection
        }

        func begin(
            continuation: CheckedContinuation<String, any Swift.Error>,
            host: String,
            port: Int,
            observedLeaf: OSAllocatedUnfairLock<String?>,
            timeout: TimeInterval
        ) {
            lock.withLock { self.continuation = continuation }
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    if let pin = observedLeaf.withLock({ $0 }) {
                        finish(.success(pin))
                    } else {
                        finish(.failure(Error.noCertificate(host: host, port: port)))
                    }
                case let .failed(error):
                    finish(.failure(Error.failed(host: host, port: port, reason: error.localizedDescription)))
                case let .waiting(error):
                    finish(.failure(Error.failed(host: host, port: port, reason: error.localizedDescription)))
                case .cancelled:
                    finish(.failure(Error.failed(host: host, port: port, reason: "cancelled")))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            // The timeout runs on the connection's queue, serialized with its state handler.
            // swiftlint:disable:next no_gcd
            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                finish(.failure(Error.timedOut(host: host, port: port)))
            }
        }

        private func finish(_ result: Result<String, any Swift.Error>) {
            let continuation = lock.withLock { () -> CheckedContinuation<String, any Swift.Error>? in
                defer { self.continuation = nil }
                return self.continuation
            }
            guard let continuation else { return }
            connection.cancel()
            continuation.resume(with: result)
        }
    }
}
