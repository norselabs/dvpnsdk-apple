//
//  NodeType.swift
//  DVPNSDK
//

import Foundation

// MARK: - NodeType

/// The protocol a backend node serves, as the backend names it. `wireguard` and `v2ray` are the original node types;
/// `xray`, `amneziawg` and `hysteria` (wire value `HYSTERIA2`) are the newer ones. `v2ray` and `xray` are both served
/// by the Xray-core tunnel; `amneziawg` rides on the WireGuard engine with extra parameters.
///
/// "All" is an app's selection, not a node type: an app asks the lists for every node type and a credentials request
/// for none, as each expects. The declaration order is the order a request names several node types in
/// (`WIREGUARD,V2RAY,XRAY,AMNEZIAWG,HYSTERIA2`).
public enum NodeType: String, Sendable, Codable, CaseIterable {
    case wireguard = "WIREGUARD"
    case v2ray = "V2RAY"
    case xray = "XRAY"
    case amneziawg = "AMNEZIAWG"
    case hysteria = "HYSTERIA2"
}

// MARK: - Wire value

extension [NodeType] {
    /// The node types as a request names them: comma-joined, in the order given.
    var wireValue: String {
        map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - CredentialsBody

/// The JSON body of a credentials request: the node types it accepts, comma-joined; with none, the key is left out.
struct CredentialsBody: Sendable {
    let nodeTypes: [NodeType]

    init(_ nodeTypes: [NodeType]) {
        self.nodeTypes = nodeTypes
    }

    init(_ nodeType: NodeType?) {
        nodeTypes = nodeType.map { [$0] } ?? []
    }
}

// MARK: - Encodable

extension CredentialsBody: Encodable {
    enum CodingKeys: String, CodingKey {
        case nodeTypes = "protocol"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !nodeTypes.isEmpty {
            try container.encode(nodeTypes.wireValue, forKey: .nodeTypes)
        }
    }
}
