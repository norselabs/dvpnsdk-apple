//
//  TunnelManager+Forget.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNWireGuardCore
import DVPNXRayCore

// MARK: - Forget

public extension TunnelManager {
    /// Deletes every engine's stored configuration: WireGuard's file, Xray's source and Hysteria's configuration,
    /// each with the directory that holds it. `restart()` then throws `.noStoredConfiguration` and `start(from:)`
    /// needs new credentials.
    ///
    /// It touches neither the tunnel profile nor a running tunnel: until a start writes a configuration again, an
    /// on-demand start by the system fails. The next `TunnelManager` in a new process turns on-demand off on such a
    /// profile and keeps it. Stop the tunnel before this call, which turns on-demand off at once.
    ///
    /// Every store is cleared even when another one fails; a failure is logged.
    nonisolated func forgetStoredConfiguration() {
        Self.forget("WireGuard") { try WireGuardFileStorage.delete() }
        Self.forget("Xray") { try XraySourceStore.delete() }
        Self.forget("Hysteria") { try HysteriaConfigurationStore.delete() }
    }
}

// MARK: - Private

private extension TunnelManager {
    nonisolated static func forget(_ engine: String, _ delete: () throws -> Void) {
        do {
            try delete()
        } catch {
            logger.error(
                "Failed to delete the stored \(engine, privacy: .public) configuration: \(error.logDescription, privacy: .public)"
            )
        }
    }
}
