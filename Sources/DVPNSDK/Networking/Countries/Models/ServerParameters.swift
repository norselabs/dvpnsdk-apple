//
//  ServerParameters.swift
//  DVPNSDK
//

import Foundation

// MARK: - ServerParameters

/// The lists' query: the node types asked for (`filter`, comma-joined) and the order, by load.
struct ServerParameters: Sendable {
    let filter: String
    let sort = "CURRENT_LOAD"

    init(nodeTypes: [NodeType]) {
        filter = nodeTypes.wireValue
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "sort", value: sort)]
    }
}
