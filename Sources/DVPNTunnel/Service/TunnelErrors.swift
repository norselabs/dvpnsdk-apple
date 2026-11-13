//
//  TunnelErrors.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import NetworkExtension

// MARK: - TunnelsServiceError

/// The SDK writes no user text: an app chooses its words by case, `isPermissionDenied` first. `description` is for
/// the log.
public enum TunnelsServiceError: Error, Sendable {
    case emptyName
    case nameAlreadyExists
    case loadTunnelsFailed(systemError: Error)
    case addTunnelFailed(systemError: Error)
    case removeTunnelFailed(systemError: Error)
    case emptyCredentials
    /// The node's address is not one the SDK dials: not an IPv4 address in four decimal numbers, an IPv6 address or a
    /// host name, or the address of this device, a private or shared network, a link, multicast, the benchmarking range,
    /// a reserved or IPv4-mapped range, or an IPv4-compatible or NAT64 address whose IPv4 is one of those
    /// (`ConnectionCredentials` refuses the same when it decodes).
    case refusedNodeAddress
    case unsupportedProtocol
    /// `TunnelManager.restart()` found nothing stored to start the tunnel from.
    case noStoredConfiguration
    case activationFailed(TunnelActivationError)
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
}

// MARK: - Equatable

extension TunnelsServiceError: Equatable {
    /// By case; a system error counts by its domain and code.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.emptyName, .emptyName), (.nameAlreadyExists, .nameAlreadyExists), (.emptyCredentials, .emptyCredentials),
             (.refusedNodeAddress, .refusedNodeAddress), (.unsupportedProtocol, .unsupportedProtocol),
             (.noStoredConfiguration, .noStoredConfiguration):
            return true
        case let (.loadTunnelsFailed(lhs), .loadTunnelsFailed(rhs)), let (.addTunnelFailed(lhs), .addTunnelFailed(rhs)),
             let (.removeTunnelFailed(lhs), .removeTunnelFailed(rhs)):
            return lhs.isSameSystemError(as: rhs)
        case let (.activationFailed(lhs), .activationFailed(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension TunnelsServiceError: CustomStringConvertible {
    public var description: String {
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
        case .refusedNodeAddress:
            return "The node's address is not a public address"
        case .unsupportedProtocol:
            return "Unsupported protocol"
        case .noStoredConfiguration:
            return "No stored configuration to restart the tunnel from"
        case let .activationFailed(error):
            return error.description
        }
    }
}

// MARK: - TunnelActivationError

public enum TunnelActivationError: Error, Sendable {
    case inactive
    case startingFailed(systemError: Error)
    case savingFailed(systemError: Error)
    case loadingFailed(systemError: Error)
    case retryLimitReached(lastSystemError: Error)
    case activationAttemptFailed(wasOnDemandEnabled: Bool)
    case timedOut
    /// The tunnel started but the server never completed the first handshake (wrong keys, dead peer, blocked UDP).
    case handshakeTimedOut
}

// MARK: - Equatable

extension TunnelActivationError: Equatable {
    /// By case; a system error counts by its domain and code.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inactive, .inactive), (.timedOut, .timedOut), (.handshakeTimedOut, .handshakeTimedOut):
            return true
        case let (.startingFailed(lhs), .startingFailed(rhs)), let (.savingFailed(lhs), .savingFailed(rhs)),
             let (.loadingFailed(lhs), .loadingFailed(rhs)), let (.retryLimitReached(lhs), .retryLimitReached(rhs)):
            return lhs.isSameSystemError(as: rhs)
        case let (.activationAttemptFailed(lhs), .activationAttemptFailed(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension TunnelActivationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .inactive:
            return "Tunnel is inactive"
        case let .startingFailed(systemError):
            return "Starting failed due to \(systemError.logDescription)"
        case let .savingFailed(systemError):
            return "Saving failed due to \(systemError.logDescription)"
        case let .loadingFailed(systemError):
            return "Loading failed due to \(systemError.logDescription)"
        case let .retryLimitReached(systemError):
            return "Reached retry limit with \(systemError.logDescription)"
        case .activationAttemptFailed:
            return "Failed to activate tunnel"
        case .timedOut:
            return "Tunnel did not respond in time"
        case .handshakeTimedOut:
            return "The server did not respond (no handshake)"
        }
    }
}

// MARK: - System errors

private extension Error {
    /// The same domain and code: what tells two system errors apart.
    func isSameSystemError(as other: any Error) -> Bool {
        let lhs = self as NSError
        let rhs = other as NSError
        return lhs.domain == rhs.domain && lhs.code == rhs.code
    }
}
