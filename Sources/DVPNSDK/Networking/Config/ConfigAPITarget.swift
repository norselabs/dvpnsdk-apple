//
//  ConfigAPITarget.swift
//  DVPNSDK
//

import Foundation

enum ConfigAPITarget {
    case getVersion(request: ConfigParameters)
}

extension ConfigAPITarget: APITarget {
    var method: HTTPMethod { .get }

    var path: String { "/config" }

    var payload: RequestPayload {
        switch self {
        case let .getVersion(request):
            return .query(request.queryItems)
        }
    }
}
