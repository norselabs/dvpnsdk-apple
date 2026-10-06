@testable import DVPNSDK
import Foundation
import Network
import Security
import Testing

// MARK: - HTTP Request Encoding

struct SNISpoofTransportEncodingTests {
    private let transport = SNISpoofTransport(timeout: 5)

    @Test
    func encodeSimpleGET() throws {
        let url = try #require(URL(string: "https://example.com/health"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = transport.encode(request: request, url: url, sni: "cover.com")
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.hasPrefix("GET /health HTTP/1.1\r\n"))
        #expect(text.contains("Host: example.com\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    @Test
    func encodePOSTWithBody() throws {
        let url = try #require(URL(string: "https://api.test.com/device"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"platform\":\"IOS\"}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = transport.encode(request: request, url: url, sni: "cover.com")
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("POST /device HTTP/1.1\r\n"))
        #expect(text.contains("Content-Length: 18\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.hasSuffix("{\"platform\":\"IOS\"}"))
    }

    @Test
    func encodePreservesQueryString() throws {
        let url = try #require(URL(string: "https://api.test.com/config?app_token=abc"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = transport.encode(request: request, url: url, sni: "cover.com")
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.hasPrefix("GET /config?app_token=abc HTTP/1.1\r\n"))
    }

    @Test
    func encodeStripsConflictingHeaders() throws {
        let url = try #require(URL(string: "https://api.test.com/health"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("custom.host.com", forHTTPHeaderField: "Host")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let data = transport.encode(request: request, url: url, sni: "cover.com")
        let text = try #require(String(data: data, encoding: .utf8))

        let hostCount = text.components(separatedBy: "Host:").count - 1
        #expect(hostCount == 1)
        #expect(text.contains("Connection: close"))
        #expect(text.contains("Accept-Encoding: gzip"))
    }

    @Test
    func encodeEmptyPathDefaultsToSlash() throws {
        let url = try #require(URL(string: "https://api.test.com"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = transport.encode(request: request, url: url, sni: "cover.com")
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.hasPrefix("GET / HTTP/1.1\r\n"))
    }
}

// MARK: - HTTP Response Parsing

struct SNISpoofTransportParsingTests {
    private let transport = SNISpoofTransport(timeout: 5)

    @Test
    func parseSimple200() throws {
        let body = "{\"data\":{\"status\":\"OK\"}}"
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
        let data = Data((header + body).utf8)

        let parsed = try transport.parseResponse(data)

        #expect(parsed.status == 200)
        #expect(parsed.headers["Content-Type"] == "application/json")
        #expect(String(data: parsed.body, encoding: .utf8) == body)
    }

    @Test
    func parse404() throws {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
        let data = Data(response.utf8)

        let parsed = try transport.parseResponse(data)

        #expect(parsed.status == 404)
        #expect(parsed.body.isEmpty)
    }

    @Test
    func parse500WithBody() throws {
        let bodyText = "{\"error\":\"internal\"}"
        let response = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: \(bodyText.count)\r\n\r\n\(bodyText)"
        let data = Data(response.utf8)

        let parsed = try transport.parseResponse(data)

        #expect(parsed.status == 500)
        #expect(String(data: parsed.body, encoding: .utf8) == bodyText)
    }

    @Test
    func throwsOnMissingHeaderSeparator() {
        let data = Data("GARBAGE WITHOUT CRLF".utf8)

        #expect(throws: SNISpoofTransport.TransportError.self) { try transport.parseResponse(data) }
    }

    @Test
    func throwsOnInvalidStatusLine() {
        let data = Data("NOT-HTTP blah\r\n\r\n".utf8)

        #expect(throws: SNISpoofTransport.TransportError.self) { try transport.parseResponse(data) }
    }

    @Test
    func parseChunkedTransferEncoding() throws {
        let header = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
        let chunks = "5\r\nHello\r\n6\r\n World\r\n0\r\n\r\n"
        let data = Data((header + chunks).utf8)

        let parsed = try transport.parseResponse(data)

        #expect(parsed.status == 200)
        #expect(String(data: parsed.body, encoding: .utf8) == "Hello World")
    }

    @Test
    func parseSingleChunk() throws {
        let json = "{\"data\":{\"status\":\"OK\"}}"
        let hex = String(json.count, radix: 16)
        let header = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
        let chunks = "\(hex)\r\n\(json)\r\n0\r\n\r\n"
        let data = Data((header + chunks).utf8)

        let parsed = try transport.parseResponse(data)

        #expect(String(data: parsed.body, encoding: .utf8) == json)
    }

    @Test
    func parseMultipleHeaders() throws {
        let body = "{}"
        let header = "HTTP/1.1 200 OK\r\nA: 1\r\nB: 2\r\nC: 3\r\n\r\n"
        let data = Data((header + body).utf8)

        let parsed = try transport.parseResponse(data)

        #expect(parsed.headers["A"] == "1")
        #expect(parsed.headers["B"] == "2")
        #expect(parsed.headers["C"] == "3")
    }
}

// MARK: - Cancellation

/// A caller that gives up ends the exchange at once, with `CancellationError`, instead of waiting out the connect's
/// timeout. 192.0.2.1 (TEST-NET-1) answers nothing, so the connect waits.
struct SNISpoofTransportCancellationTests {
    @Test
    func aCancelledSendEndsAtOnce() async throws {
        let transport = SNISpoofTransport(timeout: 10)
        let request = URLRequest(url: try #require(URL(string: "https://cover.test/health")))
        let task = Task { try await transport.send(request, ip: "192.0.2.1", sni: "cover.test", rootCAPublicKeys: [Data([1])]) }
        try await Task.sleep(for: .milliseconds(200))

        let elapsed = await ContinuousClock().measure {
            task.cancel()
            _ = await task.result
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(elapsed < .seconds(2))
    }
}

// MARK: - Connection states

/// A connection left waiting for a better path, as one whose certificate was refused is, fails the connect at once
/// instead of at its timeout.
struct SNISpoofConnectStateTests {
    private static func isFailure(_ outcome: Result<Void, any Error>?) -> Bool {
        if case .failure? = outcome {
            true
        } else {
            false
        }
    }

    @Test
    func aWaitingConnectionFailsTheConnect() {
        #expect(Self.isFailure(SNISpoofTransport.connectOutcome(of: .waiting(.tls(errSSLBadCert)))))
        #expect(Self.isFailure(SNISpoofTransport.connectOutcome(of: .waiting(.posix(.ENETUNREACH)))))
    }

    @Test
    func theConnectWaitsOnlyWhileTheConnectionIsBeingMade() {
        #expect(SNISpoofTransport.connectOutcome(of: .setup) == nil)
        #expect(SNISpoofTransport.connectOutcome(of: .preparing) == nil)
        if case .success? = SNISpoofTransport.connectOutcome(of: .ready) {} else { Issue.record("ready does not end the connect") }
        #expect(Self.isFailure(SNISpoofTransport.connectOutcome(of: .failed(.posix(.ECONNREFUSED)))))
        #expect(Self.isFailure(SNISpoofTransport.connectOutcome(of: .cancelled)))
    }
}
