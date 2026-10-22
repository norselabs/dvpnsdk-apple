//
//  MirroredTransport+Failures.swift
//  DVPNSDK
//

import Foundation

// MARK: - Failures

extension MirroredTransport {
    /// A failure as a log line names it, never printed whole: an error's user info or values can hold a file's path or
    /// a request's data. The API's errors by their answer; a mirror's or a transport's error by its case, with the
    /// domain and code of the error it wraps; anything else by its domain and code.
    static func describeFailure(_ error: any Error) -> String {
        switch error {
        case let failure as HardFailure:
            switch failure {
            case let .answer(response):
                return describe(APIError.answer(status: response.status, body: response.body))
            case let .error(error):
                return describe(error)
            }
        case let error as APIError:
            return describe(error)
        case is CancellationError:
            return "cancelled"
        case let error as MirrorError:
            return caseName(of: error)
        case let error as SNISpoofTransport.TransportError:
            switch error {
            case let .connectionFailed(wrapped), let .sendFailed(wrapped), let .receiveFailed(wrapped):
                return "\(caseName(of: error)) \(domainAndCode(of: wrapped))"
            case .invalidRootCA, .invalidStatusLine, .malformedResponse, .missingURL:
                return caseName(of: error)
            }
        default:
            return domainAndCode(of: error)
        }
    }

    /// An enum's case, without its values.
    private static func caseName(of error: any Error) -> String {
        // `Swift.`: this module has a `Mirror` of its own, the backend's.
        Swift.Mirror(reflecting: error).children.first?.label ?? String(describing: error)
    }

    private static func domainAndCode(of error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    static func describe(_ error: APIError) -> String {
        switch error {
        case .offline:
            return "offline"
        case let .unreachable(code):
            return "unreachable \(code.rawValue)"
        case let .backend(status, code):
            return "\(status) \(code ?? "-")"
        case let .invalidResponse(status):
            return "\(status) invalid response"
        }
    }

    /// The mirror path ended without an answer from any backend: no mirror to try (`MirrorError`), or a spoofed one
    /// that could not be reached. Such an error never reaches the apps, which have no words for it: the primary's
    /// answer or failure stands in for it.
    static func isNoMirrorAnswer(_ error: Error) -> Bool {
        error is MirrorError || error is SNISpoofTransport.TransportError
    }

    static func isHardFailure(_ error: Error) -> Bool {
        switch error {
        case is HardFailure:
            return true
        case let transportError as SNISpoofTransport.TransportError:
            return transportError.isHardFailure
        case let urlError as URLError:
            return isHardFailure(urlError)
        case let APIError.unreachable(code):
            return isHardFailure(URLError(code))
        case let APIError.backend(status, _):
            return isHardFailureStatus(status)
        default:
            return false
        }
    }

    private static func isHardFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .cannotLoadFromNetwork,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    /// HTTP status codes that should trigger a mirror fallback. 5xx = primary
    /// is broken; 408 = primary accepted the connection but couldn't answer
    /// in time, which a mirror may.
    static func isHardFailureStatus(_ code: Int) -> Bool {
        code == 408 || code >= 500
    }
}

private extension SNISpoofTransport.TransportError {
    /// A spoofed mirror that could not be reached or answered garbage; another mirror may work. A missing
    /// root CA or URL would fail the same way everywhere.
    var isHardFailure: Bool {
        switch self {
        case .connectionFailed, .sendFailed, .receiveFailed, .invalidStatusLine, .malformedResponse:
            true
        case .invalidRootCA, .missingURL:
            false
        }
    }
}

// MARK: - HardFailure

/// What a primary or mirror attempt ended with that another endpoint may not share: an answer (408 or 5xx) or no answer
/// at all. Internal to the transport: `send` returns the answer or throws the error.
enum HardFailure: Error {
    case answer(APIResponse)
    case error(APIError)
}
