//
//  ConnectionAPITarget.swift
//  DVPNSDK
//

import Foundation

enum ConnectionAPITarget {
    case ip
    case credentialsCity(id: String, filter: CredentialsFilter)
    case credentialsCountry(id: String, filter: CredentialsFilter)
    case credentialsServer(id: String, body: CredentialsBody)
    case quickCredentials(filter: CredentialsFilter)
}

extension ConnectionAPITarget: APITarget {
    var method: HTTPMethod {
        switch self {
        case .ip:
            return .get
        case .credentialsCity, .credentialsCountry, .credentialsServer, .quickCredentials:
            return .post
        }
    }

    var path: String {
        switch self {
        case .ip:
            return "/ip"
        case let .credentialsCity(id, _):
            return "/city/\(id)/credentials"
        case let .credentialsCountry(id, _):
            return "/country/\(id)/credentials"
        case let .credentialsServer(id, _):
            return "/server/\(id)/credentials"
        case .quickCredentials:
            return "/credentials"
        }
    }

    var payload: RequestPayload {
        switch self {
        case .ip:
            return .none
        case let .credentialsCity(_, filter), let .credentialsCountry(_, filter), let .quickCredentials(filter):
            return .query(filter.queryItems)
        case let .credentialsServer(_, body):
            return .json(body)
        }
    }
}
