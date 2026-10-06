//
//  ConfigAPIClient.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// The backend's `/config`: the lowest app version it still serves on a platform, or nil when it names none.
public struct ConfigAPIClient: Sendable {
    public var minimumVersion: @Sendable (_ appToken: String, _ platform: Platform) async throws -> VersionResponse?

    public init(minimumVersion: @escaping @Sendable (_ appToken: String, _ platform: Platform) async throws -> VersionResponse?) {
        self.minimumVersion = minimumVersion
    }
}

// MARK: - Live

public extension ConfigAPIClient {
    /// Sends through `httpClient`; the live value uses the process's.
    static func live(httpClient: any HTTPClient) -> Self {
        Self(
            minimumVersion: { appToken, platform in
                let target = ConfigAPITarget.getVersion(request: ConfigParameters(appToken: appToken))
                let request = APIRequest(target: target, timeoutInterval: RequestTimeout.config)
                return try await httpClient
                    .execute(request, as: DataResponse<[VersionResponse]>.self)
                    .data
                    .first { $0.key == platform.versionKey }
            }
        )
    }
}

// MARK: - DependencyKey

extension ConfigAPIClient: DependencyKey {
    public static let liveValue = Self.live(httpClient: ProcessHTTPClient())
    public static let testValue = Self(minimumVersion: unimplemented("ConfigAPIClient.minimumVersion"))
}

public extension DependencyValues {
    var configAPI: ConfigAPIClient {
        get { self[ConfigAPIClient.self] }
        set { self[ConfigAPIClient.self] = newValue }
    }
}
