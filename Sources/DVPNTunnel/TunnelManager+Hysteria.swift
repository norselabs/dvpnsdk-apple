//
//  TunnelManager+Hysteria.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNHysteriaCore
import DVPNSDK
import Foundation

// MARK: - Hysteria

extension TunnelManager {
    /// Builds the Hysteria configuration from backend credentials and activates the tunnel.
    func startHysteria(from credentials: ConnectionCredentials) async throws(TunnelsServiceError) {
        let descriptor = try requiredDescriptor(for: .hysteria)
        guard case let .hysteria(endpoint) = credentials.endpoint else {
            throw .emptyCredentials
        }
        try await startHysteria(configuration: Self.configuration(for: endpoint, uid: credentials.uid), descriptor: descriptor)
    }

    /// The client configuration for a backend node, as the node's own client template renders it.
    /// Node certificates are self-signed and the pin is the trust anchor, so a pinned node is dialled
    /// `insecure` like that template does. Nodes send no `auth` of their own: the client's UUID is it.
    nonisolated static func configuration(for endpoint: HysteriaEndpoint, uid: String?) -> HysteriaConfiguration {
        var configuration = HysteriaConfiguration(
            server: endpoint.host,
            port: endpoint.port,
            auth: endpoint.auth ?? uid ?? "",
            tls: .init(
                sni: endpoint.sni,
                insecure: (endpoint.insecure ?? false) || endpoint.tlsPin != nil,
                pinSHA256: endpoint.tlsPin
            )
        )
        if let password = endpoint.obfsPassword {
            configuration.obfs = .init(password: password)
        }
        return configuration
    }

    /// Stores the configuration in the App Group and activates the Hysteria tunnel.
    func startHysteria(
        configuration: HysteriaConfiguration,
        descriptor: TunnelProtocolDescriptor
    ) async throws(TunnelsServiceError) {
        let service = try await loadService()

        TunnelConfigDirectories.storeDNS(storage.selectedDNS)
        do {
            try HysteriaConfigurationStore.save(configuration)
        } catch {
            logger.error("Failed to store Hysteria configuration: \(error, privacy: .public)")
            throw .addTunnelFailed(systemError: error)
        }

        let tunnel = try await service.startProxyTunnel(descriptor, onDemandEnabled: true)
        try await activate(tunnel, in: service)
    }
}
