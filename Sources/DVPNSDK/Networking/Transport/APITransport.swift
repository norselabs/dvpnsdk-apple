//
//  APITransport.swift
//  DVPNSDK
//

import Foundation

// MARK: - APITransport

/// Where requests go: the backend through its primary and mirrors (`MirroredTransport`), or a stand-in such as a UI
/// test's. A transport routes and retries but never classifies an answer, so a stand-in's answers are classified by
/// `DefaultHTTPClient` exactly like the backend's.
public protocol APITransport: Sendable {
    /// The answer to `request`, whatever its status. Throws `APIError.offline` or `.unreachable` when no endpoint
    /// answered, and `CancellationError` when the caller was cancelled.
    func send(_ request: APIRequest, headers: [String: String]) async throws -> APIResponse

    /// Re-evaluates which endpoint, the primary or a mirror, requests go to.
    func refreshEndpoint() async
}

// MARK: - APIResponse

/// An answer as the backend sent it.
public struct APIResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data
    /// The device token the answered attempt carried, or nil if it had none.
    public let sentToken: String?

    public init(status: Int, body: Data, sentToken: String?) {
        self.status = status
        self.body = body
        self.sentToken = sentToken
    }
}

extension APIResponse {
    var isSuccess: Bool {
        (200 ..< 300).contains(status)
    }

    /// The body as `type`, or `APIError.invalidResponse`.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: body)
        } catch {
            throw APIError.invalidResponse(status: status)
        }
    }
}
