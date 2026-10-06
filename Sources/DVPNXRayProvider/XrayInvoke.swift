//
//  XrayInvoke.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation
import LibXray

// MARK: - XrayInvoke

/// Thin wrapper over libXray's single C entrypoint (`CGoInvoke`, API version 3).
///
/// Requests and responses are JSON envelopes:
/// `{"apiVersion": 3, "method": "runXray", "payload": {"xrayJson": "..."}}` →
/// `{"success": true, "data": {...}, "error": ""}`. Every response string allocated by Go
/// is released with `CGoFree` before this type returns.
enum XrayInvoke {
    static let apiVersion = 3

    struct Request<Payload: Encodable>: Encodable {
        var apiVersion = XrayInvoke.apiVersion
        let method: String
        let payload: Payload
    }

    struct Response<Payload: Decodable>: Decodable {
        let success: Bool
        let data: Payload?
        let error: String?
    }

    struct Empty: Codable {}
    struct RunXrayPayload: Encodable { let xrayJson: String }
    struct VersionData: Decodable { let version: String }
    struct StateData: Decodable { let running: Bool }

    // MARK: Methods

    static func runXray(configJSON: String) throws {
        try call("runXray", payload: RunXrayPayload(xrayJson: configJSON))
    }

    static func testXray(configJSON: String) throws {
        try call("testXray", payload: RunXrayPayload(xrayJson: configJSON))
    }

    static func stopXray() throws {
        try call("stopXray", payload: Empty())
    }

    static func xrayVersion() throws -> String {
        try call("xrayVersion", payload: Empty(), expecting: VersionData.self)?.version ?? "unknown"
    }

    static func isRunning() -> Bool {
        (try? call("getXrayState", payload: Empty(), expecting: StateData.self))?.running ?? false
    }

    // MARK: Transport

    @discardableResult
    static func call<Result: Decodable>(
        _ method: String,
        payload: some Encodable,
        expecting: Result.Type = Empty.self
    ) throws -> Result? {
        let requestData = try JSONEncoder().encode(Request(method: method, payload: payload))
        let request = String(decoding: requestData, as: UTF8.self)

        guard let rawResponse = invoke(request) else {
            throw NSError.newError("Xray \(method) returned no response")
        }

        let response: Response<Result>
        do {
            response = try JSONDecoder().decode(Response<Result>.self, from: Data(rawResponse.utf8))
        } catch {
            logger.error("Xray \(method, privacy: .public) returned an undecodable response: \(rawResponse, privacy: .public)")
            throw NSError.newError("Xray \(method) returned an undecodable response")
        }
        guard response.success else {
            throw NSError.newError("Xray \(method) failed: \(response.error ?? "unknown error")")
        }
        return response.data
    }

    /// Calls `CGoInvoke` and copies the Go-allocated response into a Swift string.
    private static func invoke(_ request: String) -> String? {
        guard let cRequest = strdup(request) else { return nil }
        defer { free(cRequest) }
        guard let cResponse = CGoInvoke(cRequest) else { return nil }
        defer { CGoFree(cResponse) }
        return String(cString: cResponse)
    }
}
