//
//  APIError.swift
//  DVPNSDK
//

import Foundation

// MARK: - APIError

/// How a request failed. The SDK classifies the failure (`reason`, `isTransient`, `deviceState`) but writes no text:
/// each app maps it to its own strings, and the backend's `reason` and the system's descriptions go to the log only.
public enum APIError: Error, Equatable, Sendable {
    /// The device has no network path, so nothing was sent.
    case offline
    /// No endpoint answered: a timeout, a host not found, a refused connection, a TLS failure.
    case unreachable(URLError.Code)
    /// The backend answered with an error: the HTTP status, and its `error` code exactly as sent, if any.
    case backend(status: Int, code: String?)
    /// The backend answered with success, but not with what the request expects.
    case invalidResponse(status: Int)
}

public extension APIError {
    /// The HTTP status of an error the backend answered with.
    var status: Int? {
        guard case let .backend(status, _) = self else { return nil }
        return status
    }

    /// The backend's `error` code, as sent; a code the SDK does not know (another API's, say) is the caller's to match.
    var backendCode: String? {
        guard case let .backend(_, code) = self else { return nil }
        return code
    }

    /// What the failure means, for the cases apps tell apart: the backend's code when the SDK knows it, otherwise the
    /// status or the connection failure.
    var reason: Reason? {
        switch self {
        case .offline:
            return .noConnection
        case let .unreachable(code):
            return Reason(urlErrorCode: code)
        case let .backend(status, code):
            return code.flatMap(Reason.init(rawValue:)) ?? Reason(status: status)
        case .invalidResponse:
            return .unknownError
        }
    }

    /// Whether the backend could not be reached or could not answer, as opposed to refusing the request: screens keep
    /// showing what they have.
    var isTransient: Bool {
        switch reason {
        case .timedOut, .noConnection, .temporaryUnavailable, .serverUnavailable, .tlsError, .redirectionError:
            return true
        case .unknownError, .invalidRequest, .notFound, .unauthorizedDevice, .deviceBanned, .deviceNotEnrolled,
             .appIsNotGenuine, .appIsInactive, nil:
            return false
        }
    }

    /// The device's state the failure reveals, if any. The backend's code decides: a code the SDK does not know
    /// describes something other than the device; without a code, 401, 403 and 425 do.
    var deviceState: DeviceState? {
        guard case let .backend(status, code) = self else { return nil }
        if let code {
            switch Reason(rawValue: code) {
            case .unauthorizedDevice:
                return .unauthorized
            case .deviceBanned:
                return .banned
            case .deviceNotEnrolled:
                return .notEnrolled
            case .appIsInactive:
                return .appInactive
            default:
                return nil
            }
        }
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .banned
        case 425:
            return .notEnrolled
        default:
            return nil
        }
    }
}

// MARK: - Reason

public extension APIError {
    /// The raw values of the backend's cases are its `error` codes; the tests pin them.
    enum Reason: String, Sendable, CaseIterable {
        case unknownError
        case timedOut
        case noConnection
        case tlsError
        case redirectionError
        case invalidRequest
        case notFound
        case unauthorizedDevice
        case deviceBanned = "bannedDevice"
        case deviceNotEnrolled
        case temporaryUnavailable
        case serverUnavailable
        case appIsNotGenuine
        case appIsInactive = "appInactive"
    }
}

extension APIError.Reason {
    init?(status: Int) {
        switch status {
        case 301, 302:
            self = .redirectionError
        case 400:
            self = .invalidRequest
        case 401:
            self = .unauthorizedDevice
        case 403:
            self = .deviceBanned
        case 404:
            self = .notFound
        case 408:
            self = .timedOut
        case 410:
            self = .serverUnavailable
        case 425:
            self = .deviceNotEnrolled
        case 500:
            self = .unknownError
        case 501 ... 511:
            self = .temporaryUnavailable
        default:
            return nil
        }
    }

    init?(urlErrorCode code: URLError.Code) {
        switch code {
        case .timedOut:
            self = .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            self = .noConnection
        case .secureConnectionFailed:
            self = .tlsError
        default:
            return nil
        }
    }
}

// MARK: - From an answer

extension APIError {
    /// The failure an error answer describes: its status and the `error` code of its body, if it has one.
    static func answer(status: Int, body: Data) -> APIError {
        .backend(status: status, code: (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error)
    }
}

/// The backend's error body; `reason` is for the log only.
struct ErrorBody: Decodable {
    let error: String
    let reason: String?
}
