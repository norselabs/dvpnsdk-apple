//
//  SNISpoofTransport.swift
//  DVPNSDK
//

import Foundation
import Network
import Security

/// HTTP/1.1 over TLS to an IP with an explicit SNI name, trusting only a leaf certificate that one of the caller's root
/// CA keys signed; the system's trust store, the hostname and the validity dates are not consulted.
struct SNISpoofTransport: Sendable {
    enum TransportError: Error {
        case connectionFailed(Error)
        case sendFailed(Error)
        case receiveFailed(Error)
        case invalidRootCA
        case invalidStatusLine
        case malformedResponse
        case missingURL
    }

    let timeout: TimeInterval

    func send(
        _ request: URLRequest,
        ip: String,
        sni: String,
        rootCAPublicKeys: [Data]
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw TransportError.missingURL }
        try Task.checkCancellation()

        let parameters = makeParameters(sni: sni, rootCAPublicKeys: rootCAPublicKeys)
        let host = NWEndpoint.Host(ip)
        let port: NWEndpoint.Port = .init(integerLiteral: 443)
        let connection = NWConnection(host: host, port: port, using: parameters)

        let queue = DispatchQueue(label: "dvpnsdk.sni-spoof.\(UUID().uuidString)")

        // A cancelled caller cancels the connection, which ends the connect, send or receive it waits on, and gets a
        // `CancellationError`, not a transport failure that would drop a working mirror.
        let raw: Data
        do {
            raw = try await withTaskCancellationHandler {
                try await exchange(request, url: url, sni: sni, connection: connection, queue: queue)
            } onCancel: {
                connection.cancel()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }

        let response = try parseResponse(raw)
        let (status, headers, body) = (response.status, response.headers, response.body)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) ?? HTTPURLResponse()
        return (body, httpResponse)
    }
}

// MARK: - TLS options

private extension SNISpoofTransport {
    /// Creates NWParameters with TLS configured for SNI spoofing.
    func makeParameters(sni: String, rootCAPublicKeys: [Data]) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions

        sni.withCString { sec_protocol_options_set_tls_server_name(secOptions, $0) }

        sec_protocol_options_set_verify_block(secOptions, { _, sec_trust, complete in
            let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
            complete(Self.isSignedByTrustedRoot(trust, rootCAPublicKeys: rootCAPublicKeys))
        }, DispatchQueue(label: "dvpnsdk.sni-spoof.verify"))

        let parameters = NWParameters(tls: tlsOptions)
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = Int(timeout)
            tcp.noDelay = true
        }
        return parameters
    }
}

// MARK: - Trust

extension SNISpoofTransport {
    /// Whether the leaf, the first certificate the mirror presented, carries a signature one of `rootCAPublicKeys`
    /// verifies. Mirrors present only the leaf (an X.509 v1 certificate without extensions), so the root is not in
    /// the chain: the check verifies the leaf's signature over its `tbsCertificate` with each root key.
    /// `rootCAPublicKeys` are RSA keys as DER, SubjectPublicKeyInfo or PKCS#1, of any size.
    static func isSignedByTrustedRoot(_ trust: SecTrust, rootCAPublicKeys: [Data]) -> Bool {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              let parsed = parseX509Signature(SecCertificateCopyData(leaf) as Data)
        else {
            return false
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        return rootCAPublicKeys.contains { keyData in
            guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) else { return false }
            return SecKeyVerifySignature(key, parsed.algorithm, parsed.tbs as CFData, parsed.signature as CFData, nil)
        }
    }

    /// The parts of a DER certificate that a signature check needs.
    struct X509Signature {
        let tbs: Data
        let signature: Data
        let algorithm: SecKeyAlgorithm
    }

    // One guard per DER tag on the way to the signature.
    // swiftlint:disable:next cyclomatic_complexity
    static func parseX509Signature(_ certData: Data) -> X509Signature? {
        var offset = 0

        guard skipTag(&offset, in: certData, expected: 0x30) else { return nil }
        guard skipLength(&offset, in: certData) != nil else { return nil }

        let tbsStart = offset
        guard skipTag(&offset, in: certData, expected: 0x30) else { return nil }
        guard let tbsContentLen = skipLength(&offset, in: certData) else { return nil }
        offset += tbsContentLen
        let tbsCertificate = certData[tbsStart ..< offset]

        guard skipTag(&offset, in: certData, expected: 0x30) else { return nil }
        guard let algLen = skipLength(&offset, in: certData) else { return nil }
        let algStart = offset
        offset += algLen
        let algBytes = certData[algStart ..< offset]

        guard skipTag(&offset, in: certData, expected: 0x03) else { return nil }
        guard let sigLen = skipLength(&offset, in: certData) else { return nil }
        guard offset < certData.count else { return nil }

        let unusedBits = certData[offset]
        offset += 1
        guard unusedBits == 0x00 else { return nil }
        let signature = certData[offset ..< (offset + sigLen - 1)]

        guard let algorithm = mapAlgorithm(Data(algBytes)) else { return nil }

        return X509Signature(tbs: Data(tbsCertificate), signature: Data(signature), algorithm: algorithm)
    }

    // MARK: - ASN.1 helpers

    private static func skipTag(_ offset: inout Int, in data: Data, expected: UInt8) -> Bool {
        guard offset < data.count, data[offset] == expected else { return false }
        offset += 1
        return true
    }

    private static func skipLength(_ offset: inout Int, in data: Data) -> Int? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        offset += 1

        if first < 0x80 {
            return Int(first)
        }

        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4, offset + numBytes <= data.count else { return nil }

        var length = 0
        for _ in 0 ..< numBytes {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }

    /// Maps a DER-encoded AlgorithmIdentifier body to a SecKeyAlgorithm.
    private static func mapAlgorithm(_ algBytes: Data) -> SecKeyAlgorithm? {
        let sha256OID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]
        let sha384OID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0c]
        let sha512OID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0d]
        let sha1OID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x05]

        if algBytes.containsSequence(sha256OID) { return .rsaSignatureMessagePKCS1v15SHA256 }
        if algBytes.containsSequence(sha384OID) { return .rsaSignatureMessagePKCS1v15SHA384 }
        if algBytes.containsSequence(sha512OID) { return .rsaSignatureMessagePKCS1v15SHA512 }
        if algBytes.containsSequence(sha1OID)   { return .rsaSignatureMessagePKCS1v15SHA1 }

        return nil
    }
}

// MARK: - Connection lifecycle

extension SNISpoofTransport {
    /// What a connection state means for the connect: done, failed, or nil to keep waiting. A waiting connection has
    /// failed too: a refused certificate or a missing route leaves it waiting for a better path, which would hold a
    /// probe or a request until its timeout.
    static func connectOutcome(of state: NWConnection.State) -> Result<Void, any Error>? {
        switch state {
        case .ready:
            return .success(())
        case let .waiting(error), let .failed(error):
            return .failure(TransportError.connectionFailed(error))
        case .cancelled:
            return .failure(TransportError.connectionFailed(URLError(.cancelled)))
        default:
            return nil
        }
    }
}

private extension SNISpoofTransport {
    /// Connects, sends `request` and reads the whole answer. The exchange after the connect has the same bound as the
    /// connect, so a mirror that accepts the connection and then stalls is given up.
    func exchange(
        _ request: URLRequest,
        url: URL,
        sni: String,
        connection: NWConnection,
        queue: DispatchQueue
    ) async throws -> Data {
        try await withConnectionTimeout(connection: connection, queue: queue)
        defer { connection.cancel() }
        // Cancelling the connection fails the pending send or receive.
        // swiftlint:disable:next no_gcd
        queue.asyncAfter(deadline: .now() + timeout) { connection.cancel() }

        try await sendAll(connection, data: encode(request: request, url: url, sni: sni))
        return try await receiveAll(connection)
    }

    func withConnectionTimeout(connection: NWConnection, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = ManagedAtomicFlag()
            connection.stateUpdateHandler = { state in
                guard let outcome = Self.connectOutcome(of: state) else { return }
                // A waiting connection would try again by itself, and nothing else cancels it.
                if case .waiting = state { connection.cancel() }
                if resumed.set() { continuation.resume(with: outcome) }
            }
            connection.start(queue: queue)

            // The timeout runs on the connection's queue, serialized with its state handler.
            // swiftlint:disable:next no_gcd
            queue.asyncAfter(deadline: .now() + timeout) {
                if resumed.set() {
                    connection.cancel()
                    continuation.resume(throwing: TransportError.connectionFailed(URLError(.timedOut)))
                }
            }
        }
    }

    func sendAll(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TransportError.sendFailed(error))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receiveAll(_ connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            let chunk: (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: TransportError.receiveFailed(error))
                        return
                    }
                    continuation.resume(returning: (data, isComplete))
                }
            }
            if let data = chunk.0 { buffer.append(data) }
            if chunk.1 { break }
        }
        return buffer
    }
}

// MARK: - HTTP encoding / parsing

extension SNISpoofTransport {
    func encode(request: URLRequest, url: URL, sni: String) -> Data {
        let method = request.httpMethod ?? "GET"
        let path = (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? "")
        let host = url.host ?? sni

        var lines: [String] = []
        lines.append("\(method) \(path) HTTP/1.1")
        lines.append("Host: \(host)")
        lines.append("Connection: close")

        var seenContentLength = false
        request.allHTTPHeaderFields?.forEach { key, value in
            if key.caseInsensitiveCompare("Host") == .orderedSame { return }
            if key.caseInsensitiveCompare("Connection") == .orderedSame { return }
            if key.caseInsensitiveCompare("Content-Length") == .orderedSame { seenContentLength = true }
            lines.append("\(key): \(value)")
        }

        let body = request.httpBody ?? Data()
        if !seenContentLength, !body.isEmpty {
            lines.append("Content-Length: \(body.count)")
        }

        let head = lines.joined(separator: "\r\n") + "\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(body)
        return packet
    }

    /// A raw HTTP/1.1 response split into its status, headers and (de-chunked) body.
    struct RawHTTPResponse {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    func parseResponse(_ raw: Data) throws -> RawHTTPResponse {
        let separator = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let range = raw.range(of: separator) else { throw TransportError.malformedResponse }
        let headerData = raw.subdata(in: 0 ..< range.lowerBound)
        let body = raw.subdata(in: range.upperBound ..< raw.count)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw TransportError.malformedResponse
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw TransportError.invalidStatusLine }
        let statusComponents = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard statusComponents.count >= 2, let status = Int(statusComponents[1]) else {
            throw TransportError.invalidStatusLine
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headers[key] = value }
        }

        let isChunked = headers.first(where: { $0.key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame })?
            .value.lowercased().contains("chunked") ?? false

        let resolvedBody = isChunked ? (try decodeChunked(body)) : body
        return RawHTTPResponse(status: status, headers: headers, body: resolvedBody)
    }

    func decodeChunked(_ data: Data) throws -> Data {
        var output = Data()
        var index = data.startIndex
        let crlf = Data([0x0d, 0x0a])

        while index < data.endIndex {
            guard let lineEnd = data.range(of: crlf, in: index ..< data.endIndex) else { break }
            let sizeLine = data.subdata(in: index ..< lineEnd.lowerBound)
            guard let sizeString = String(data: sizeLine, encoding: .utf8)?
                .components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces),
                let size = Int(sizeString, radix: 16)
            else {
                throw TransportError.malformedResponse
            }
            index = lineEnd.upperBound
            if size == 0 { break }
            guard data.endIndex >= index + size + 2 else { throw TransportError.malformedResponse }
            output.append(data.subdata(in: index ..< (index + size)))
            index += size + 2 // skip trailing CRLF
        }
        return output
    }
}

// MARK: - Data helpers

private extension Data {
    func containsSequence(_ bytes: [UInt8]) -> Bool {
        let target = Data(bytes)
        return range(of: target) != nil
    }
}

// MARK: - Single-shot continuation flag

// `@unchecked`: the flag is only read and written under its lock.
private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    /// Returns true the first time it's called; false on every subsequent call.
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
