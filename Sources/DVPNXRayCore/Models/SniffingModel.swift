//
//  SniffingModel.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

// MARK: - TunnelConfigDirectories: sniffing

extension TunnelConfigDirectories {
    static let sniffing: String = "XRAY_SNIFFIN_DATA"
}

// MARK: - SniffingModel

struct SniffingModel: Codable, Equatable, Sendable {
    let enabled: Bool
    let destOverride: [String]
    let metadataOnly: Bool
    let routeOnly: Bool
    let excludedDomains: [String]
}

// MARK: - Storage

extension SniffingModel {
    /// `routeOnly`: a sniffed name only chooses a route, and the node connects to the address the device looked up
    /// through its chosen DNS. Without it the node looks every name up again with its own resolver and uses that answer.
    static let `default` = SniffingModel(
        enabled: true,
        destOverride: ["http", "tls"],
        metadataOnly: false,
        routeOnly: true,
        excludedDomains: []
    )

    static var current: SniffingModel {
        do {
            guard let data = UserDefaults.shared.data(forKey: TunnelConfigDirectories.sniffing) else {
                return .default
            }
            return try JSONDecoder().decode(SniffingModel.self, from: data)
        } catch {
            return .default
        }
    }
}
