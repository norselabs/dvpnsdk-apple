//
//  NetworkModel.swift
//  DVPNCore
//

import Foundation

// MARK: - TunnelConfigDirectories: network

public extension TunnelConfigDirectories {
    static let network: String = "NETWORK_DATA"
}

// MARK: - NetworkModel

public struct NetworkModel: Codable, Equatable, Sendable {
    public let hideVPNIcon: Bool
    public let ipv6Enabled: Bool

    public init(hideVPNIcon: Bool, ipv6Enabled: Bool) {
        self.hideVPNIcon = hideVPNIcon
        self.ipv6Enabled = ipv6Enabled
    }
}

// MARK: - Storage

public extension NetworkModel {
    static let `default` = NetworkModel(
        hideVPNIcon: false,
        ipv6Enabled: false
    )

    static var current: NetworkModel {
        do {
            guard let data = UserDefaults.shared.data(forKey: TunnelConfigDirectories.network) else {
                return .default
            }
            return try JSONDecoder().decode(NetworkModel.self, from: data)
        } catch {
            return .default
        }
    }

    /// Persists this model to the shared App Group so the tunnel extension picks it up on next start.
    func save() throws {
        let data = try JSONEncoder().encode(self)
        UserDefaults.shared.set(data, forKey: TunnelConfigDirectories.network)
    }
}
