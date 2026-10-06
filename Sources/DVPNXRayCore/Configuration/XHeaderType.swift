//
//  XHeaderType.swift
//  DVPNCore
//

import Foundation

// MARK: - XHeaderType

public enum XHeaderType: String, Identifiable, CaseIterable, Codable, Sendable {
    public var id: Self { self }

    case none
    case srtp
    case utp
    case wechat_video = "wechat-video"
    case dtls
    case wireguard
}
