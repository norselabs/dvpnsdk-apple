//
//  DVPNCoreConfiguration.swift
//  DVPNCore
//

import Foundation
import Synchronization

// MARK: - DVPNCoreConfiguration

/// Per-application values injected by the host app. A white-label app supplies
/// its own identifiers here instead of editing the core.
public struct DVPNCoreConfiguration: Sendable {
    public let appGroupID: String

    /// The tunnel engines this app ships, one packet tunnel extension each.
    /// Protocols absent from this list are reported as unsupported by the tunnel layer.
    public let protocols: [TunnelProtocolDescriptor]
    /// The transparent-proxy extension that lets apps bypass the VPN (macOS); nil in an app without one.
    public let splitTunnelProviderBundleID: String?

    public init(appGroupID: String, protocols: [TunnelProtocolDescriptor], splitTunnelProviderBundleID: String? = nil) {
        precondition(
            Set(protocols.map(\.id)).count == protocols.count,
            "DVPNCoreConfiguration: every TunnelProtocolID may appear once"
        )
        precondition(
            Set(protocols.map(\.providerBundleID)).count == protocols.count,
            "DVPNCoreConfiguration: provider bundle identifiers must be unique"
        )
        precondition(
            !protocols.contains { $0.providerBundleID == splitTunnelProviderBundleID },
            "DVPNCoreConfiguration: the split-tunnel extension is not a tunnel engine"
        )
        self.appGroupID = appGroupID
        self.protocols = protocols
        self.splitTunnelProviderBundleID = splitTunnelProviderBundleID
    }
}

// MARK: - Lookups

public extension DVPNCoreConfiguration {
    func descriptor(for id: TunnelProtocolID) -> TunnelProtocolDescriptor? {
        protocols.first { $0.id == id }
    }

    func descriptor(forProviderBundleID bundleID: String?) -> TunnelProtocolDescriptor? {
        guard let bundleID else { return nil }
        return protocols.first { $0.providerBundleID == bundleID }
    }

    func supports(_ id: TunnelProtocolID) -> Bool {
        descriptor(for: id) != nil
    }

    /// Traps when the app did not declare `id`; use `descriptor(for:)` for optional lookups.
    func requiredDescriptor(for id: TunnelProtocolID) -> TunnelProtocolDescriptor {
        guard let descriptor = descriptor(for: id) else {
            preconditionFailure("DVPNCoreConfiguration does not declare the \(id.rawValue) protocol")
        }
        return descriptor
    }
}

// MARK: - DVPNCore

public enum DVPNCore {
    /// Call once from the app's composition root before any tunnel or storage API is used.
    /// Network extensions do not call this — they resolve the App Group through
    /// the `DVPNAppGroupIdentifier` Info.plist key instead.
    public static func bootstrap(_ configuration: DVPNCoreConfiguration) {
        TunnelEnvironment.setConfiguration(configuration)
    }
}

// MARK: - TunnelEnvironment

/// Process-wide access to the injected configuration and the shared App Group (package-internal:
/// the apps go through `DVPNCore.bootstrap` and the public APIs).
package enum TunnelEnvironment {
    package static let infoPlistKey = "DVPNAppGroupIdentifier"

    /// `@unchecked`: UserDefaults is thread-safe by contract, but Foundation marks its Sendable conformance unavailable.
    private struct SharedDefaults: @unchecked Sendable {
        let defaults: UserDefaults
    }

    private struct State: Sendable {
        var configuration: DVPNCoreConfiguration?
        var cachedDefaults: SharedDefaults?
    }

    private static let state = Mutex(State())

    package static var configuration: DVPNCoreConfiguration? {
        state.withLock { $0.configuration }
    }

    /// The configuration set by `DVPNCore.bootstrap(_:)`; traps when the app forgot to call it.
    package static var requiredConfiguration: DVPNCoreConfiguration {
        guard let configuration else {
            preconditionFailure("DVPNCore.bootstrap(_:) must be called before using this API")
        }
        return configuration
    }

    static func setConfiguration(_ configuration: DVPNCoreConfiguration) {
        state.withLock { $0.configuration = configuration }
    }

    /// Resolved from the bootstrapped configuration in the app, or from the
    /// `DVPNAppGroupIdentifier` Info.plist key inside network extensions.
    package static var appGroupID: String {
        if let configuration { return configuration.appGroupID }
        if let identifier = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String {
            return identifier
        }
        preconditionFailure("Set \(infoPlistKey) in Info.plist or call DVPNCore.bootstrap(_:)")
    }

    package static var sharedDefaults: UserDefaults {
        if let cached = state.withLock({ $0.cachedDefaults }) {
            return cached.defaults
        }
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            preconditionFailure("Unable to open shared UserDefaults for App Group \(appGroupID)")
        }
        let shared = SharedDefaults(defaults: defaults)
        return state.withLock { current in
            if let cached = current.cachedDefaults { return cached }
            current.cachedDefaults = shared
            return shared
        }.defaults
    }
}
