//
//  APIErrorTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Testing

/// How an answer or a failed connection becomes an `APIError`, and what the error says: its reason, whether it is
/// transient, and the device state it reveals.
struct APIErrorTests {
    // MARK: - From an answer

    @Test
    func anErrorBodyGivesTheStatusAndTheCode() {
        let body = Data(#"{"error":"bannedDevice","reason":"device is banned"}"#.utf8)
        #expect(APIError.answer(status: 403, body: body) == .backend(status: 403, code: "bannedDevice"))
    }

    @Test
    func anAnswerWithoutAnErrorBodyHasNoCode() {
        #expect(APIError.answer(status: 500, body: Data("Internal Server Error".utf8)) == .backend(status: 500, code: nil))
        #expect(APIError.answer(status: 502, body: Data()) == .backend(status: 502, code: nil))
    }

    @Test
    func aSuccessIsDecoded() throws {
        let response = APIResponse(status: 200, body: Data(#"{"data":{"status":"OK"}}"#.utf8), sentToken: nil)
        #expect(try response.decoded(as: HealthResponse.self).data.status == "OK")
    }

    @Test
    func aSuccessThatDoesNotDecodeIsAnInvalidResponse() {
        let response = APIResponse(status: 200, body: Data("not json".utf8), sentToken: nil)
        #expect(throws: APIError.invalidResponse(status: 200)) { try response.decoded(as: HealthResponse.self) }
    }

    // MARK: - Reason

    /// Every code the backend sends, with the status it comes with. A code without a case of its own is classified
    /// by the status.
    @Test(arguments: [
        ("unknownError", 500, APIError.Reason.unknownError),
        ("invalidRequest", 400, .invalidRequest),
        ("notFound", 404, .notFound),
        ("unauthorizedDevice", 401, .unauthorizedDevice),
        ("somethingElse", 401, .unauthorizedDevice),
        ("bannedDevice", 403, .deviceBanned),
        ("appInactive", 403, .appIsInactive),
        ("deviceNotEnrolled", 425, .deviceNotEnrolled),
        ("serverInactive", 503, .temporaryUnavailable),
        ("unauthorizedAccount", 400, .invalidRequest),
        ("unauthorizedApplication", 400, .invalidRequest),
    ])
    func mapsEachBackendCode(code: String, status: Int, expected: APIError.Reason) {
        // Production leaves the reason empty.
        let body = Data(#"{"error":"\#(code)","reason":""}"#.utf8)
        #expect(APIError.answer(status: status, body: body).reason == expected)
    }

    @Test(arguments: [
        (401, APIError.Reason.unauthorizedDevice),
        (403, .deviceBanned),
        (425, .deviceNotEnrolled),
        (404, .notFound),
        (408, .timedOut),
        (410, .serverUnavailable),
        (500, .unknownError),
        (501, .temporaryUnavailable),
        (503, .temporaryUnavailable),
        (511, .temporaryUnavailable),
    ])
    func mapsEachStatusWithoutACode(status: Int, expected: APIError.Reason) {
        #expect(APIError.backend(status: status, code: nil).reason == expected)
    }

    /// A request that fails before it reaches the backend carries a URL error's code. Every way the network or the
    /// backend's address cannot be reached reads as no connection.
    @Test(arguments: [
        (URLError.Code.timedOut, APIError.Reason.timedOut),
        (.notConnectedToInternet, .noConnection),
        (.networkConnectionLost, .noConnection),
        (.cannotFindHost, .noConnection),
        (.cannotConnectToHost, .noConnection),
        (.dnsLookupFailed, .noConnection),
        (.secureConnectionFailed, .tlsError),
    ])
    func mapsEachURLErrorCode(code: URLError.Code, expected: APIError.Reason) {
        #expect(APIError.unreachable(code).reason == expected)
    }

    @Test
    func noNetworkPathIsNoConnection() {
        #expect(APIError.offline.reason == .noConnection)
    }

    @Test
    func anInvalidResponseIsAnUnknownError() {
        #expect(APIError.invalidResponse(status: 200).reason == .unknownError)
    }

    // MARK: - Transient

    /// The backend could not be reached or answer: screens keep what they show.
    @Test(arguments: [
        APIError.offline,
        .unreachable(.timedOut),
        .unreachable(.notConnectedToInternet),
        .unreachable(.cannotFindHost),
        .unreachable(.cannotConnectToHost),
        .unreachable(.dnsLookupFailed),
        .unreachable(.secureConnectionFailed),
        .backend(status: 503, code: "serverInactive"),
    ])
    func anUnreachableBackendIsTransient(error: APIError) {
        #expect(error.isTransient)
    }

    /// The backend refused the request.
    @Test(arguments: [
        APIError.backend(status: 400, code: "invalidRequest"),
        .backend(status: 401, code: "somethingElse"),
        .backend(status: 404, code: "notFound"),
        .backend(status: 500, code: "unknownError"),
        .invalidResponse(status: 200),
    ])
    func aRefusedRequestIsNotTransient(error: APIError) {
        #expect(!error.isTransient)
    }

    // MARK: - Device state

    @Test(arguments: [
        (APIError.backend(status: 401, code: "unauthorizedDevice"), DeviceState?.some(.unauthorized)),
        (.backend(status: 401, code: nil), .unauthorized),
        (.backend(status: 403, code: "bannedDevice"), .banned),
        (.backend(status: 403, code: nil), .banned),
        (.backend(status: 403, code: "appInactive"), .appInactive),
        (.backend(status: 425, code: "deviceNotEnrolled"), .notEnrolled),
        (.backend(status: 425, code: nil), .notEnrolled),
    ])
    func aRefusalForTheDeviceRevealsItsState(error: APIError, expected: DeviceState?) {
        #expect(error.deviceState == expected)
    }

    /// A code the SDK does not know describes something other than the device (another API's refusal, say): it must
    /// not make the app drop the device's token.
    @Test(arguments: [
        APIError.backend(status: 401, code: "somethingElse"),
        .backend(status: 403, code: "invalidRequest"),
        .backend(status: 400, code: nil),
        .backend(status: 404, code: "notFound"),
        .unreachable(.timedOut),
        .offline,
    ])
    func anyOtherFailureRevealsNoDeviceState(error: APIError) {
        #expect(error.deviceState == nil)
    }
}
