//
//  DeviceAPIClient.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// Registers the device, which returns its token, and verifies it: whether the backend has enrolled it.
public struct DeviceAPIClient: Sendable {
    public var register: @Sendable (_ platform: Platform, _ appToken: String) async throws -> DeviceToken
    public var verify: @Sendable () async throws -> VerifyDeviceResponse

    public init(
        register: @escaping @Sendable (_ platform: Platform, _ appToken: String) async throws -> DeviceToken,
        verify: @escaping @Sendable () async throws -> VerifyDeviceResponse
    ) {
        self.register = register
        self.verify = verify
    }
}

// MARK: - Live

public extension DeviceAPIClient {
    /// Sends through `httpClient`; the live value uses the process's.
    static func live(httpClient: any HTTPClient) -> Self {
        Self(
            register: { platform, appToken in
                let body = RegisterDeviceRequest(platform: platform.rawValue, appToken: appToken)
                let request = APIRequest(target: DeviceAPITarget.registerDevice(body))
                return try await httpClient.execute(request, as: DataResponse<DeviceToken>.self).data
            },
            verify: {
                try await httpClient.execute(APIRequest(target: DeviceAPITarget.getDevice), as: DataResponse<VerifyDeviceResponse>.self).data
            }
        )
    }
}

// MARK: - DependencyKey

extension DeviceAPIClient: DependencyKey {
    public static let liveValue = Self.live(httpClient: ProcessHTTPClient())

    public static let testValue = Self(
        register: unimplemented("DeviceAPIClient.register"),
        verify: unimplemented("DeviceAPIClient.verify")
    )
}

public extension DependencyValues {
    var deviceAPI: DeviceAPIClient {
        get { self[DeviceAPIClient.self] }
        set { self[DeviceAPIClient.self] = newValue }
    }
}
