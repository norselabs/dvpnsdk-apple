//
//  Mirror.swift
//  DVPNSDK
//

import Foundation

enum MirrorType: String, Decodable, Sendable {
    case regular = "REGULAR"
    case sniSpoof = "SNI_SPOOF"
}

struct Mirror: Decodable, Sendable {
    let type: MirrorType
    let endpoint: String
    let availableSniOptions: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case endpoint
        case availableSniOptions = "available_sni_options"
    }
}

struct HealthResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let status: String
    }

    let data: Payload
}

enum MirrorError: Error {
    case noHealthyMirror
    case bootstrapFailed
    case invalidEndpoint
    case invalidResponse
}
