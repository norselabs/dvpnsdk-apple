//
//  NetworkModel.swift
//  DVPNSDK
//

import Foundation

// MARK: - NetworkModel

public struct NetworkModel: Codable, Equatable, Sendable {
    public let hideVPNIcon: Bool
    public let ipv6Enabled: Bool

    public init(hideVPNIcon: Bool, ipv6Enabled: Bool) {
        self.hideVPNIcon = hideVPNIcon
        self.ipv6Enabled = ipv6Enabled
    }
}

// MARK: - Default

public extension NetworkModel {
    /// What the proxy providers run with when the app stored nothing else: the VPN icon shown, IPv6 left out.
    static let `default` = NetworkModel(
        hideVPNIcon: false,
        ipv6Enabled: false
    )

    /// The default with IPv6 as `options` route it.
    init(options: TunnelNetworkOptions) {
        self.init(hideVPNIcon: NetworkModel.default.hideVPNIcon, ipv6Enabled: options.ipv6 == .tunnel)
    }
}
