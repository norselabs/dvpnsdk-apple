//
//  TunnelManager+Restart.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNWireGuardCore
import DVPNXRayCore
import Foundation
import WireGuardKit

// MARK: - Restart

extension TunnelManager {
    /// Starts the tunnel again on the node it last used, with the DNS and obfuscation settings as they are now, so a
    /// change to either applies without new credentials. A running tunnel is stopped first. Returns once connected,
    /// as `start(from:)` does.
    ///
    /// Throws `.noStoredConfiguration`, and leaves the tunnel as it is, when nothing is stored to start it from: no
    /// tunnel was started yet, or the system purged the configuration (tvOS may purge it from its caches).
    public func restart() async throws(TunnelsServiceError) {
        let service = try await loadService()
        guard let tunnel = service.tunnels.last, let stored = storedStart(of: tunnel) else {
            throw .noStoredConfiguration
        }
        await service.startDeactivationOfActiveTunnel()

        switch stored {
        case let .wireGuard(configuration):
            try await service.modify(
                tunnel: tunnel,
                isOnDemandEnabled: true,
                tunnelConfiguration: Self.configuration(configuration, withDNS: storage.selectedDNS)
            )
            try await activate(tunnel, in: service)
        case var .xray(model):
            model.obfuscation = selectedObfuscation
            try await startXray(source: .model(model), descriptor: try requiredDescriptor(for: .xray))
        case let .hysteria(configuration):
            try await startHysteria(configuration: configuration, descriptor: try requiredDescriptor(for: .hysteria))
        }
    }

    /// `configuration` with `dns` as its resolvers; the keys, the peer and any AmneziaWG parameters stay.
    static func configuration(_ configuration: TunnelConfiguration, withDNS dns: DNSServerType) -> TunnelConfiguration {
        var interface = configuration.interface
        interface.dns = dns.addresses.compactMap { DNSServer(from: $0) }
        interface.dnsSearch = []
        return TunnelConfiguration(name: configuration.name, interface: interface, peers: configuration.peers)
    }
}

// MARK: - Private

private extension TunnelManager {
    /// What the last start stored for the tunnel's engine: WireGuard's in its profile, the proxy engines' in the App
    /// Group.
    enum StoredStart {
        case wireGuard(TunnelConfiguration)
        case xray(XConfigurationModel)
        case hysteria(HysteriaConfiguration)
    }

    func storedStart(of tunnel: TunnelContainer) -> StoredStart? {
        switch tunnel.descriptor?.id {
        case .wireGuard:
            return tunnel.tunnelConfiguration.map { .wireGuard($0) }
        case .xray:
            guard case let .model(model) = try? XraySourceStore.loadCurrent() else { return nil }
            return .xray(model)
        case .hysteria:
            return (try? HysteriaConfigurationStore.loadCurrent()).map { .hysteria($0) }
        case nil:
            return nil
        }
    }
}
