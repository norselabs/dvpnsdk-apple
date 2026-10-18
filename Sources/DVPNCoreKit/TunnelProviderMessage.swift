//
//  TunnelProviderMessage.swift
//  DVPNSDK
//

import Foundation

// MARK: - TunnelProviderMessage

/// What the app asks a running DVPN packet tunnel provider (`NETunnelProviderSession.sendProviderMessage`), one byte
/// per message. A provider answers nil to a message it does not know, as one built before the message existed does.
package enum TunnelProviderMessage: UInt8, Sendable {
    /// WireGuard: the engine's runtime configuration (UAPI `get=1` text), WireGuardKit's own message.
    case runtimeConfiguration = 0
    /// Every engine: connect to the node of the configuration the app stored since the tunnel started, keeping the tunnel
    /// interface and its routes. Answered with a `NodeSwitchReply`.
    case switchNode = 1

    package init?(_ data: Data) {
        guard data.count == 1, let message = Self(rawValue: data[data.startIndex]) else { return nil }
        self = message
    }

    package var data: Data {
        Data([rawValue])
    }
}

// MARK: - NodeSwitchReply

/// A provider's answer to `TunnelProviderMessage.switchNode`.
package enum NodeSwitchReply: Equatable, Sendable {
    /// The engine runs on the new node.
    case switched
    /// The engine could not switch, for the reason given (for the log). The tunnel interface stays up.
    case failed(String)

    package init?(_ data: Data) {
        guard let kind = data.first else { return nil }
        switch kind {
        case 0:
            self = .switched
        case 1:
            self = .failed(String(decoding: data.dropFirst(), as: UTF8.self))
        default:
            return nil
        }
    }

    package var data: Data {
        switch self {
        case .switched:
            return Data([0])
        case let .failed(reason):
            return Data([1]) + Data(reason.utf8)
        }
    }
}
