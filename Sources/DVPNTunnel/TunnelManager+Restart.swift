//
//  TunnelManager+Restart.swift
//  DVPNSDK
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNWireGuardCore
import DVPNXRayCore
import Foundation
import WireGuardKit

// MARK: - Restart

extension TunnelManager {
    /// Starts the tunnel again on the node it last used, with the DNS, obfuscation and network settings as they are now,
    /// so a change to any of them applies without new credentials. A running tunnel is stopped first. Returns once
    /// connected, as `start(from:)` does.
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
                tunnelConfiguration: applyingSettings(to: configuration),
                networkOptions: storage.networkOptions
            )
            try await activate(tunnel, in: service)
        case var .xray(model):
            model.obfuscation = selectedObfuscation
            try await startXray(source: .model(model), descriptor: try requiredDescriptor(for: .xray))
        case let .hysteria(configuration):
            try await startHysteria(configuration: configuration, descriptor: try requiredDescriptor(for: .hysteria))
        }
    }

    /// A WireGuard configuration with the DNS and IPv6 settings as they are now, as every start and restart writes it.
    /// `nodeAddresses`: the addresses the node assigned, when the configuration is a node's first.
    func applyingSettings(to configuration: TunnelConfiguration, nodeAddresses: [String] = []) -> TunnelConfiguration {
        let ipv6 = storage.networkOptions.ipv6
        return Self.configuration(
            Self.configuration(configuration, withDNS: storage.dnsConfiguration, includingIPv6: ipv6 == .tunnel),
            routingIPv6: ipv6,
            nodeAddresses: nodeAddresses
        )
    }

    /// `configuration` with `dns` as its resolvers, over HTTPS when `dns` has a DoH URL; the keys, the peer and any
    /// AmneziaWG parameters stay. The IPv6 servers are left out unless the tunnel routes IPv6 (`includingIPv6`).
    static func configuration(_ configuration: TunnelConfiguration, withDNS dns: DNSConfiguration, includingIPv6: Bool) -> TunnelConfiguration {
        var interface = configuration.interface
        interface.dns = dns.servers(includingIPv6: includingIPv6).compactMap { DNSServer(from: $0) }
        interface.dnsSearch = []
        interface.dnsOverHTTPSURL = dns.isEncrypted ? dns.dohURL : nil
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
