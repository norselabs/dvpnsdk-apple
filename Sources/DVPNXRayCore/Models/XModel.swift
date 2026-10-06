//
//  XModel.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

// MARK: - TunnelConfigDirectories: route

extension TunnelConfigDirectories {
    static let route: String = "XRAY_ROUTE_DATA"
}

// MARK: - XModel

struct XModel: Codable, Equatable, Sendable {
    var domainStrategy: DomainStrategy = .asIs
    var domainMatcher: DomainMatcher = .hybrid
    var rules: [Rule] = []
    var balancers: [Balancer] = []
}

// MARK: - Storage

extension XModel {
    static let `default` = XModel()
    static var current: XModel {
        do {
            guard let data = UserDefaults.shared.data(forKey: TunnelConfigDirectories.route) else {
                return .default
            }
            return try JSONDecoder().decode(XModel.self, from: data)
        } catch {
            return .default
        }
    }
}

// MARK: - Submodels

extension XModel {
    // MARK: - DomainStrategy

    enum DomainStrategy: String, Identifiable, CaseIterable, Codable, Sendable {
        var id: Self { self }
        case asIs = "AsIs"
        case ipIfNonMatch = "IPIfNonMatch"
        case ipOnDemand = "IPOnDemand"
    }

    // MARK: - DomainMatcher

    enum DomainMatcher: String, Identifiable, CaseIterable, Codable, Sendable {
        var id: Self { self }
        case hybrid
        case linear
    }

    // MARK: - Outbound

    enum Outbound: String, Identifiable, CaseIterable, Codable, Sendable {
        var id: Self { self }
        case direct
        case proxy
        case block
    }

    // MARK: - Rule

    struct Rule: Codable, Equatable, Identifiable, Sendable {
        var id: UUID { __id__ }

        var domainMatcher: DomainMatcher = .hybrid
        var type: String = "field"
        var domain: [String]?
        var ip: [String]?
        var port: String?
        var sourcePort: String?
        var network: String?
        var source: [String]?
        var user: [String]?
        var inboundTag: [String]?
        var `protocol`: [String]?
        var attrs: String?
        var outboundTag: Outbound = .direct
        var balancerTag: String?

        var __id__: UUID = .init()
        var __name__: String = ""
        var __enabled__: Bool = false

        var __defaultName__: String {
            "Rule_\(__id__.uuidString)"
        }

        init() {}
    }

    // MARK: - Balancer

    struct Balancer: Codable, Equatable, Sendable {
        var tag: String
        var selector: [String] = []

        init(tag: String, selector: [String] = []) {
            self.tag = tag
            self.selector = selector
        }
    }
}
