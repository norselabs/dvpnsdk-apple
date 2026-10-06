//
//  TunnelStatus.swift
//  DVPNCore
//

import Foundation
import NetworkExtension

public enum TunnelStatus: Int, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case reasserting

    case restarting
    case waiting

    public init(from status: NEVPNStatus) {
        switch status {
        case .connected:
            self = .connected
        case .connecting:
            self = .connecting
        case .disconnected:
            self = .disconnected
        case .disconnecting:
            self = .disconnecting
        case .reasserting:
            self = .reasserting
        case .invalid:
            self = .disconnected
        @unknown default:
            self = .disconnected
        }
    }

    public var isActive: Bool { self == .connected }
}
