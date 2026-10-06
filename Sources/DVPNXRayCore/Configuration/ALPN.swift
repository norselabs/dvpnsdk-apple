//
//  ALPN.swift
//  DVPNCore
//

import Foundation

// MARK: - ALPN

public enum ALPN: String, Identifiable, CaseIterable, Codable, Sendable {
    public var id: Self { self }

    case h2
    case http1_1 = "http/1.1"
}
