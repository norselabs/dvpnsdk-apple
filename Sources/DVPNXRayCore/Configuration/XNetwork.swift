//
//  XNetwork.swift
//  DVPNCore
//

import Foundation

// MARK: - XNetwork

public enum XNetwork: String, Identifiable, CaseIterable, Codable, Sendable {
    public var id: Self { self }

    case tcp
    case ws
    case grpc
    case xhttp
    case httpupgrade
}
