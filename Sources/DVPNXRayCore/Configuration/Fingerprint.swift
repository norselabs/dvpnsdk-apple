//
//  Fingerprint.swift
//  DVPNCore
//

import Foundation

// MARK: - Fingerprint

public enum Fingerprint: String, Identifiable, CaseIterable, Codable, Sendable {
    public var id: Self { self }

    case chrome
    case firefox
    case safari
    case ios
    case android
    case edge
    case _360 = "360"
    case qq
    case random
    case randomized
}
