//
//  TunnelManager+IPv6.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import Network
import WireGuardKit

// MARK: - IPv6 (WireGuard)

extension TunnelManager {
    /// The interface address a WireGuard tunnel takes for IPv6 when the node assigned the client none: a unique local
    /// address (RFC 4193), which the node does not accept from this client, so IPv6 traffic enters the tunnel and ends
    /// there instead of going around it.
    static let placeholderIPv6Address = "fd6e:a81b:704f:1212::2"

    /// `configuration` with IPv6 routed as `mode` says.
    ///
    /// - `.tunnel`: every peer takes all of IPv6 (`::/0`), and the interface the node's IPv6 addresses among
    ///   `nodeAddresses` or, when the node assigned none, `placeholderIPv6Address`.
    /// - `.unchanged`: what `.tunnel` adds comes out again (`::/0` and the placeholder), so a configuration stored with
    ///   IPv6 tunnelled routes it as WireGuard nodes always did once the option is off; nothing else changes.
    static func configuration(
        _ configuration: TunnelConfiguration,
        routingIPv6 mode: TunnelNetworkOptions.IPv6Mode,
        nodeAddresses: [String] = []
    ) -> TunnelConfiguration {
        guard let allIPv6 = IPAddressRange(from: "::/0"),
              let placeholder = IPAddressRange(from: "\(placeholderIPv6Address)/128")
        else { return configuration }

        var interface = configuration.interface
        var peers = configuration.peers
        switch mode {
        case .tunnel:
            let nodeIPv6 = nodeAddresses
                .compactMap { IPAddressRange(from: "\($0)/128") }
                .filter { $0.address is IPv6Address }
            for address in nodeIPv6 where !interface.addresses.contains(address) {
                interface.addresses.append(address)
            }
            if !interface.addresses.contains(where: { $0.address is IPv6Address }) {
                interface.addresses.append(placeholder)
            }
            for index in peers.indices where !peers[index].allowedIPs.contains(allIPv6) {
                peers[index].allowedIPs.append(allIPv6)
            }
        case .unchanged:
            interface.addresses.removeAll { $0 == placeholder }
            for index in peers.indices {
                peers[index].allowedIPs.removeAll { $0 == allIPv6 }
            }
        }
        return TunnelConfiguration(name: configuration.name, interface: interface, peers: peers)
    }
}
