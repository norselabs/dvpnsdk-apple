@testable import DVPNSDK
import Foundation
import Testing

// MARK: - Hard Failure Classification

struct HardFailureTests {
    // MARK: - URLError hard failures

    @Test
    func timeoutIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.timedOut)))
    }

    @Test
    func cannotConnectIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.cannotConnectToHost)))
    }

    @Test
    func dnsLookupFailedIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.dnsLookupFailed)))
    }

    @Test
    func notConnectedIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.notConnectedToInternet)))
    }

    @Test
    func secureConnectionFailedIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.secureConnectionFailed)))
    }

    @Test
    func serverCertUntrustedIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.serverCertificateUntrusted)))
    }

    @Test
    func networkConnectionLostIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.networkConnectionLost)))
    }

    @Test
    func cannotFindHostIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(URLError(.cannotFindHost)))
    }

    // MARK: - URLError non-hard failures

    @Test
    func cancelledIsNotHardFailure() {
        #expect(!(MirroredTransport.isHardFailure(URLError(.cancelled))))
    }

    @Test
    func badURLIsNotHardFailure() {
        #expect(!(MirroredTransport.isHardFailure(URLError(.badURL))))
    }

    @Test
    func badServerResponseIsNotHardFailure() {
        #expect(!(MirroredTransport.isHardFailure(URLError(.badServerResponse))))
    }

    // MARK: - Error answers

    @Test
    func aServerErrorIsHardFailure() {
        #expect(MirroredTransport.isHardFailure(APIError.backend(status: 500, code: "unknownError")))
        #expect(MirroredTransport.isHardFailure(APIError.backend(status: 502, code: nil)))
    }

    @Test
    func aRefusalIsNotHardFailure() {
        for status in [400, 401, 403] {
            #expect(!MirroredTransport.isHardFailure(APIError.backend(status: status, code: nil)), "\(status)")
        }
    }

    @Test
    func anUnreachableEndpointIsHardFailureAsItsURLErrorIs() {
        #expect(MirroredTransport.isHardFailure(APIError.unreachable(.timedOut)))
        #expect(!MirroredTransport.isHardFailure(APIError.unreachable(.badURL)))
    }

    // MARK: - MirrorError

    @Test
    func mirrorErrorIsNotHardFailure() {
        #expect(!MirroredTransport.isHardFailure(MirrorError.noHealthyMirror))
        #expect(!MirroredTransport.isHardFailure(MirrorError.bootstrapFailed))
        #expect(!MirroredTransport.isHardFailure(MirrorError.invalidEndpoint))
    }

    /// No mirror, or a spoofed one out of reach, leaves the answer to the primary; a mirror's own answer does not.
    @Test
    func aMissingOrUnreachableMirrorIsNoAnswer() {
        #expect(MirroredTransport.isNoMirrorAnswer(MirrorError.bootstrapFailed))
        #expect(MirroredTransport.isNoMirrorAnswer(SNISpoofTransport.TransportError.connectionFailed(URLError(.timedOut))))
        #expect(!MirroredTransport.isNoMirrorAnswer(APIError.backend(status: 503, code: nil)))
        #expect(!MirroredTransport.isNoMirrorAnswer(HardFailure.answer(APIResponse(status: 503, body: Data(), sentToken: nil))))
    }

    // MARK: - Log text

    /// The log gets the status and the backend's code, which the apps no longer show.
    @Test
    func aFailureIsLoggedWithItsStatusAndCode() {
        #expect(MirroredTransport.describeFailure(APIError.backend(status: 429, code: "rateLimited")) == "429 rateLimited")
        let answer = APIResponse(status: 503, body: Data(#"{"error":"serverInactive"}"#.utf8), sentToken: nil)
        #expect(MirroredTransport.describeFailure(HardFailure.answer(answer)) == "503 serverInactive")
        #expect(MirroredTransport.describeFailure(HardFailure.error(.unreachable(.timedOut))) == "unreachable -1001")
        #expect(MirroredTransport.describeFailure(MirrorError.noHealthyMirror) == "noHealthyMirror")
    }
}

// MARK: - Host Replacement

struct HostReplacementTests {
    @Test
    func replacesHost() throws {
        let url = try #require(URL(string: "https://api.example.com/country"))
        let result = try MirroredTransport.replaceHost(in: url, with: "mirror.example.com")

        #expect(result.host == "mirror.example.com")
        #expect(result.path == "/country")
        #expect(result.scheme == "https")
    }

    @Test
    func preservesPathAndQuery() throws {
        let url = try #require(URL(string: "https://api.example.com/config?app_token=abc123"))
        let result = try MirroredTransport.replaceHost(in: url, with: "mirror.test.net")

        #expect(result.host == "mirror.test.net")
        #expect(result.path == "/config")
        #expect(result.query == "app_token=abc123")
    }

    @Test
    func preservesPort() throws {
        let url = try #require(URL(string: "https://api.example.com:8443/health"))
        let result = try MirroredTransport.replaceHost(in: url, with: "mirror.com")

        #expect(result.host == "mirror.com")
        #expect(result.port == 8443)
    }

    @Test
    func replaceHostWithIPv4() throws {
        let url = try #require(URL(string: "https://api.example.com/health"))
        let result = try MirroredTransport.replaceHost(in: url, with: "10.0.0.1")

        #expect(result.host == "10.0.0.1")
        #expect(result.path == "/health")
    }
}

// MARK: - Header Injection

struct HeaderInjectionTests {
    @Test
    func applyHeadersAddsAllEntries() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com/path")))
        MirroredTransport.applyHeaders(
            ["X-Route": "1", "X-Debug": "on"],
            to: &request
        )

        #expect(request.value(forHTTPHeaderField: "X-Route") == "1")
        #expect(request.value(forHTTPHeaderField: "X-Debug") == "on")
    }

    @Test
    func applyHeadersIsIdempotentForSameKey() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com")))
        MirroredTransport.applyHeaders(["X-Route": "1"], to: &request)
        MirroredTransport.applyHeaders(["X-Route": "1"], to: &request)

        #expect(request.value(forHTTPHeaderField: "X-Route") == "1")
    }

    @Test
    func applyHeadersOverwritesPriorValue() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com")))
        request.setValue("0", forHTTPHeaderField: "X-Route")
        MirroredTransport.applyHeaders(["X-Route": "2"], to: &request)

        #expect(request.value(forHTTPHeaderField: "X-Route") == "2")
    }

    @Test
    func applyHeadersWithEmptyDictIsNoOp() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com")))
        request.setValue("keep", forHTTPHeaderField: "X-Keep")
        MirroredTransport.applyHeaders([:], to: &request)

        #expect(request.value(forHTTPHeaderField: "X-Keep") == "keep")
        #expect(request.value(forHTTPHeaderField: "X-Route") == nil)
    }

    /// `requestHeaders` are the only header source — they're applied identically
    /// on primary and mirror paths. Multiple entries all land on the request.
    @Test
    func applyHeadersPreservesMultipleEntries() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com")))
        MirroredTransport.applyHeaders(
            ["Authorization": "Bearer X", "X-Route": "1"],
            to: &request
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer X")
        #expect(request.value(forHTTPHeaderField: "X-Route") == "1")
    }
}
