//
//  XraySource.swift
//  DVPNCore
//

import Foundation

// MARK: - XraySource

/// What the Xray extension starts from. Stored as `configs/XRAY_CURRENT/config.json` with a `kind`
/// discriminator so the format can grow without breaking stored files.
///
/// - `model`: the backend-credentials path, fully typed and rendered by `XConfigurationModel.proxyOutbound()`.
public enum XraySource: Sendable, Equatable {
    case model(XConfigurationModel)
}

// MARK: - Codable

extension XraySource: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case model
    }

    private enum Kind: String, Codable {
        case model
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .model:
            self = .model(try container.decode(XConfigurationModel.self, forKey: .model))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .model(model):
            try container.encode(Kind.model, forKey: .kind)
            try container.encode(model, forKey: .model)
        }
    }
}
