//
//  XraySecurityResolver.swift
//  DVPNCore
//

import DVPNXRayCore
import os

// MARK: - XraySecurityResolver

/// Resolves `XSecurity.autodetect` right before Xray-core starts: one handshake with the node decides
/// between TLS pinned to the certificate the node presented and plaintext. Other cases pass through.
///
/// A handshake that does not complete (refused, reset, TLS alert, no network, timeout) means plaintext,
/// exactly as the former app-side probe treated it; Xray then reports the connection error if the node
/// was in fact TLS-only.
enum XraySecurityResolver {
    static func resolve(_ model: XConfigurationModel) async -> XConfigurationModel {
        guard case let .autodetect(tls) = model.security else { return model }
        let host = model.outbound.address
        let port = model.outbound.port
        var resolved = model
        do {
            let pin = try await TLSLeafProbe.observeLeafSHA256(
                host: host,
                port: port,
                serverName: tls.serverName.isEmpty ? nil : tls.serverName
            )
            var pinned = tls
            pinned.pinnedPeerCertSha256 = pin
            resolved.security = .tls(pinned)
            logger.info("TLS detected on \(host, privacy: .public):\(port, privacy: .public); pinned leaf \(pin, privacy: .public)")
        } catch {
            resolved.security = .none
            logger.info(
                "No TLS on \(host, privacy: .public):\(port, privacy: .public) (\(error.localizedDescription, privacy: .public)); using plaintext"
            )
        }
        return resolved
    }
}
