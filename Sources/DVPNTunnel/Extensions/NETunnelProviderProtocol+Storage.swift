//
//  NETunnelProviderProtocol+Storage.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNWireGuardCore
import DVPNXRayCore
import NetworkExtension

/// Dispatches per-protocol configuration storage. WireGuard keeps a config file in the
/// App Group (`DVPNWireGuardCore`); proxy engines (Xray, Hysteria) carry no per-tunnel
/// reference in the provider protocol, their configs are written independently.
extension NETunnelProviderProtocol {
    var tunnelDescriptor: TunnelProtocolDescriptor? {
        TunnelEnvironment.requiredConfiguration
            .descriptor(forProviderBundleID: providerBundleIdentifier)
    }

    var tunnelProtocolID: TunnelProtocolID? {
        tunnelDescriptor?.id
    }

    /// `false` when the provider's engine has no stored configuration on disk to start from.
    func hasStoredConfiguration() -> Bool {
        switch tunnelProtocolID {
        case .wireGuard:
            return verifyConfigurationReference()
        case .xray:
            return XraySourceStore.exists()
        case .hysteria:
            return HysteriaConfigurationStore.exists()
        case nil:
            return true
        }
    }

    func destroyStoredConfiguration() {
        switch tunnelProtocolID {
        case .wireGuard:
            destroyConfigurationReference()
        case .xray, .hysteria, nil:
            break
        }
    }
}
