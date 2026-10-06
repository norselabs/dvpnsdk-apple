//
//  RegisterDeviceRequest.swift
//  DVPNSDK
//

import Foundation

// MARK: - RegisterDeviceRequest

struct RegisterDeviceRequest: Sendable {
    let platform: String
    let appToken: String
}

// MARK: - Encodable

extension RegisterDeviceRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case platform
        case appToken = "app_token"
    }
}
