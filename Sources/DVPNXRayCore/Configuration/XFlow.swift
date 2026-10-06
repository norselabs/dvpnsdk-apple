//
//  XFlow.swift
//  DVPNCore
//

import Foundation

// MARK: - XFlow

/// VLESS flow control. Only `xtls-rprx-vision` is meaningful for clients (TCP + TLS/Reality).
public enum XFlow: String, Identifiable, CaseIterable, Codable, Sendable {
    public var id: Self { self }

    case xtlsRprxVision = "xtls-rprx-vision"
}
