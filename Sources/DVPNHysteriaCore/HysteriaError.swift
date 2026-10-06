//
//  HysteriaError.swift
//  DVPNCore
//

import Foundation

public enum HysteriaError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case noStoredConfiguration

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Hysteria config directory does not exist"
        case .noStoredConfiguration:
            return "No stored Hysteria configuration"
        }
    }
}
