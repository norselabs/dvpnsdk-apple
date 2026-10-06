//
//  BackendConfiguration.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// Which backend this process talks to, and the device token its requests carry. The SDK has no default: the app sets
/// it once at launch, before the first request, and the clients read it when they are first used:
///
///     prepareDependencies {
///         $0.backendConfiguration = BackendConfiguration(
///             backendURL: url, mirrorListURLs: copies, rootCAPublicKeys: [key], deviceTokenProvider: keychain
///         )
///     }
public struct BackendConfiguration: Sendable {
    public var backendURL: URL
    /// Copies of the mirror list outside the backend, asked together with the backend's own `/mirrors` when the
    /// backend cannot be reached; the first list to answer wins. The SDK knows no address of its own.
    public var mirrorListURLs: [URL]
    /// The public keys of the root CAs that sign the SNI mirrors' certificates, as DER (SubjectPublicKeyInfo or
    /// PKCS#1); more than one while a key is rotated. Without one, SNI mirrors are not used.
    public var rootCAPublicKeys: [Data]
    /// Where requests read the device token they send (`x-device-token`); without one they send none.
    public var deviceTokenProvider: (any DeviceTokenProvider)?
    public var mirrorRequestTimeout: TimeInterval

    public init(
        backendURL: URL,
        mirrorListURLs: [URL] = [],
        rootCAPublicKeys: [Data] = [],
        deviceTokenProvider: (any DeviceTokenProvider)? = nil,
        mirrorRequestTimeout: TimeInterval = 5
    ) {
        self.backendURL = backendURL
        self.mirrorListURLs = mirrorListURLs
        self.rootCAPublicKeys = rootCAPublicKeys
        self.deviceTokenProvider = deviceTokenProvider
        self.mirrorRequestTimeout = mirrorRequestTimeout
    }
}

extension BackendConfiguration {
    /// Where the mirror list is fetched from: the backend's own `/mirrors` first, then the copies.
    var bootstrapMirrorURLs: [URL] {
        [backendURL.appendingPathComponent("mirrors")] + mirrorListURLs
    }
}

// MARK: - DependencyKey

private enum BackendConfigurationKey: DependencyKey {
    // A computed value because there is nothing to store: reaching it means the app skipped its setup.
    // swiftlint:disable:next dependency_values_are_constants
    static var liveValue: BackendConfiguration {
        preconditionFailure(
            "DVPNSDK has no default backend. Set one before the first request, e.g. in the app delegate: "
                + "prepareDependencies { $0.backendConfiguration = BackendConfiguration(backendURL: …) }"
        )
    }

    static let testValue = BackendConfiguration(backendURL: URL(string: "https://backend.test")!)
    static let previewValue = testValue
}

public extension DependencyValues {
    var backendConfiguration: BackendConfiguration {
        get { self[BackendConfigurationKey.self] }
        set { self[BackendConfigurationKey.self] = newValue }
    }
}
