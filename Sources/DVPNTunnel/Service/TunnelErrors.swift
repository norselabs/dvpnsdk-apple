//
//  TunnelErrors.swift
//  DVPNCore
//

import Foundation
import NetworkExtension

// MARK: - TunnelsServiceError

public enum TunnelsServiceError: LocalizedError, Sendable {
    case emptyName
    case nameAlreadyExists

    case loadTunnelsFailed(systemError: Error)
    case addTunnelFailed(systemError: Error)
    case removeTunnelFailed(systemError: Error)

    case emptyCredentials
    case unsupportedProtocol

    case activationFailed(TunnelActivationError)
}

// MARK: - Equatable

extension TunnelsServiceError: Equatable {
    public static func == (lhs: TunnelsServiceError, rhs: TunnelsServiceError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

public extension TunnelsServiceError {
    /// The user declined the system's "Add VPN Configurations" prompt: saving the profile failed with
    /// NetworkExtension's "permission denied" (`configurationReadWriteFailed`). The apps show their permission text
    /// only then, and one plain message for every other failed start.
    var isPermissionDenied: Bool {
        guard case let .addTunnelFailed(systemError) = self else { return false }
        let error = systemError as NSError
        return error.domain == NEVPNErrorDomain && error.code == NEVPNError.Code.configurationReadWriteFailed.rawValue
    }

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "The name of tunnel is empty"
        case .nameAlreadyExists:
            return "The name of tunnel already exist"
        case .loadTunnelsFailed:
            return "Fail to load tunnel"
        case .addTunnelFailed:
            return "Please allow the tunnel creation to connect to your session"
        case .removeTunnelFailed:
            return "Failed to remove tunnel"
        case .emptyCredentials:
            return "Failed to parse connection data"
        case .unsupportedProtocol:
            return "Unsupported protocol"
        case let .activationFailed(error):
            return error.errorDescription
        }
    }
}

// MARK: - TunnelActivationError

public enum TunnelActivationError: LocalizedError, Sendable {
    case inactive
    case startingFailed(systemError: Error)
    case savingFailed(systemError: Error)
    case loadingFailed(systemError: Error)
    case retryLimitReached(lastSystemError: Error)
    case activationAttemptFailed(wasOnDemandEnabled: Bool)
    case timedOut
    /// The tunnel started but the server never completed the first handshake (wrong keys, dead peer, blocked UDP).
    case handshakeTimedOut

    public var errorDescription: String? {
        switch self {
        case .inactive:
            return "Tunnel is inactive"
        case let .startingFailed(systemError):
            return "Starting failed due to \(systemError.localizedDescription)"
        case let .savingFailed(systemError):
            return "Saving failed due to \(systemError.localizedDescription)"
        case let .loadingFailed(systemError):
            return "Loading failed due to \(systemError.localizedDescription)"
        case let .retryLimitReached(systemError):
            return "Reached retry limit with \(systemError.localizedDescription)"
        case .activationAttemptFailed:
            return "Failed to activate tunnel"
        case .timedOut:
            return "Tunnel did not respond in time"
        case .handshakeTimedOut:
            return "The server did not respond (no handshake)"
        }
    }
}
