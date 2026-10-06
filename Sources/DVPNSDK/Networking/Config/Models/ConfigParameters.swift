//
//  ConfigParameters.swift
//  DVPNSDK
//

import Foundation

// MARK: - ConfigParameters

/// `/config`'s query: the app's token.
struct ConfigParameters: Sendable {
    let appToken: String

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "app_token", value: appToken)]
    }
}
