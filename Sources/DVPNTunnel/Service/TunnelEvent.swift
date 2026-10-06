//
//  TunnelEvent.swift
//  DVPNCore
//

import Foundation

/// The single event channel of the tunnel layer.
///
/// `status` reports the effective status of the managed tunnel (`TunnelsService.tunnels.last`),
/// `.disconnected` when there is none. `error` reports failures that happen outside a caller's
/// `start()`/`stop()` call (system- or on-demand-initiated activations).
public enum TunnelEvent: Sendable {
    case status(TunnelStatus)
    case error(TunnelActivationError)
}
