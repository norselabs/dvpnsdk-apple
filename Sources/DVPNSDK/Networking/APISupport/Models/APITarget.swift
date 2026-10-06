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
    /// is broadcast as `.unauthorized`, `.banned`, `.unenrolled` or `.isInactive`. Requests that fail with
    /// these codes for their own reasons, such as a sign-in with a wrong password, return `false`.
    var reportsDeviceState: Bool { get }
}

public extension APITarget {
    var reportsDeviceState: Bool { true }
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
}
