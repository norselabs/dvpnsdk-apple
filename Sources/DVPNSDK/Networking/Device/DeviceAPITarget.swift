//
//  DeviceAPITarget.swift
//  DVPNSDK
//

import Foundation

enum DeviceAPITarget {
    case registerDevice(RegisterDeviceRequest)
    case getDevice
}

extension DeviceAPITarget: APITarget {
    var method: HTTPMethod {
        switch self {
        case .registerDevice:
            return .post
        case .getDevice:
            return .get
        }
    }

    var path: String {
        switch self {
        case .registerDevice, .getDevice:
            return "/device"
        }
    }

    var payload: RequestPayload {
        switch self {
        case let .registerDevice(body):
            return .json(body)
        case .getDevice:
            return .none
        }
    }
}
