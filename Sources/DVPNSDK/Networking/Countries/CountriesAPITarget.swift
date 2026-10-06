//
//  CountriesAPITarget.swift
//  DVPNSDK
//

import Foundation

enum CountriesAPITarget {
    case countries(params: ServerParameters)
    case country(countryID: String)
    case cities(countryID: String, params: ServerParameters)
    case cityServers(cityID: String, params: ServerParameters)
}

extension CountriesAPITarget: APITarget {
    var method: HTTPMethod { .get }

    var path: String {
        switch self {
        case .countries:
            return "/country"
        case let .country(id):
            return "/country/\(id)"
        case let .cities(countryID, _):
            return "/country/\(countryID)/city"
        case let .cityServers(cityID, _):
            return "/city/\(cityID)/server"
        }
    }

    var payload: RequestPayload {
        switch self {
        case let .countries(params), let .cities(_, params), let .cityServers(_, params):
            return .query(params.queryItems)
        case .country:
            return .none
        }
    }
}
