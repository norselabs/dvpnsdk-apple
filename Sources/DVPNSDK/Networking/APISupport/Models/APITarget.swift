//
//  APITarget.swift
//  DVPNSDK
//

import Foundation

/// One backend endpoint: how to call it and what to send. Areas implement it with an enum
/// (`CountriesAPITarget`, …); an app can do the same for endpoints of its own behind the same mirrors.
public protocol APITarget: Sendable {
    var method: HTTPMethod { get }
    /// Appended to the backend URL; empty for the root.
    var path: String { get }
    var payload: RequestPayload { get }
    /// Whether a 401, 403 or 425 (or an `appIsInactive` error) from this request describes the device, and
    /// is broadcast as `.unauthorized`, `.banned`, `.notEnrolled` or `.appInactive`. Requests that fail with
    /// these codes for their own reasons, such as a sign-in with a wrong password, return `false`.
    var reportsDeviceState: Bool { get }
}

public extension APITarget {
    var reportsDeviceState: Bool { true }
}

extension APITarget {
    /// The path as the log shows it: a segment that is not a word, which could be a device's or an account's ID, is
    /// "…". A short code of letters, such as a country's, stays; a short number does not.
    var loggedPath: String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                let isCode = segment.count <= 3 && segment.allSatisfy(\.isLetter)
                let isWord = segment.allSatisfy { $0.isLowercase || $0 == "-" || $0 == "_" }
                return isCode || isWord ? String(segment) : "…"
            }
            .joined(separator: "/")
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// What a request carries besides its path.
public enum RequestPayload: Sendable {
    case none
    /// A JSON body encoded from the value.
    case json(any Encodable & Sendable)
    /// URL query items, sent in name order.
    case query([URLQueryItem])
    /// URL query items, sent in name order, and a JSON body encoded from the value.
    case queryAndJSON([URLQueryItem], any Encodable & Sendable)
}

extension RequestPayload {
    /// The query items it sends, if any.
    var queryItems: [URLQueryItem] {
        switch self {
        case let .query(items), let .queryAndJSON(items, _): items
        case .none, .json: []
        }
    }

    /// The value its JSON body is encoded from, if it has one.
    var jsonBody: (any Encodable & Sendable)? {
        switch self {
        case let .json(body), let .queryAndJSON(_, body): body
        case .none, .query: nil
        }
    }
}
