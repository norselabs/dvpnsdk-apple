//
//  DeviceToken.swift
//  DVPNSDK
//

// MARK: - DeviceToken

/// The device token the backend hands out at registration; sent as `x-device-token`.
public struct DeviceToken: Codable, Equatable, Sendable {
    public var id: String
    public var token: String

    public init(id: String, token: String) {
        self.id = id
        self.token = token
    }
}

/// Where the app keeps the device token; the SDK only reads it.
public protocol DeviceTokenProvider: Sendable {
    var deviceToken: DeviceToken? { get }
}
