//
//  XrayDocumentBuilder.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

// MARK: - XrayDocumentBuilder

/// Wraps a `proxy` outbound into the complete Xray-core configuration the extension runs:
/// a local SOCKS inbound with a password (what hev-socks5-tunnel connects to), routing, `direct`/`block` outbounds
/// and the asset directory around any proxy outbound object.
public enum XrayDocumentBuilder {
    public static let proxyTag = "proxy"
    public static let inboundTag = "socks-in"
    /// The `freedom` outbound that fragments TLS ClientHellos; the proxy outbound dials through it
    /// (`sockopt.dialerProxy`) when `XObfuscation.tlsFragment` is on.
    public static let fragmentTag = "fragment"

    /// - Parameter supportingOutbounds: outbounds the proxy outbound refers to (e.g. its `dialerProxy`);
    ///   placed right after it, before `direct`/`block`.
    public static func build(
        proxyOutbound: [String: Any],
        supportingOutbounds: [[String: Any]] = [],
        localProxy: LocalProxy,
        assetDirectory: String? = nil
    ) throws -> Data {
        let document = try document(
            proxyOutbound: proxyOutbound,
            supportingOutbounds: supportingOutbounds,
            localProxy: localProxy,
            assetDirectory: assetDirectory
        )
        return try JSONSerialization.data(withJSONObject: document, options: .prettyPrinted)
    }

    public static func document(
        proxyOutbound: [String: Any],
        supportingOutbounds: [[String: Any]] = [],
        localProxy: LocalProxy,
        assetDirectory: String? = nil
    ) throws -> [String: Any] {
        var proxy = proxyOutbound
        proxy["tag"] = proxyTag

        var configuration: [String: Any] = [:]
        if let assetDirectory {
            // libXray no longer takes a `datDir`; Xray-core reads its environment from the config root.
            configuration["env"] = ["xray.location.asset": assetDirectory]
        }
        configuration["inbounds"] = [try inbound(localProxy)]
        var route = XModel.current
        configuration["routing"] = try route.build()
        configuration["outbounds"] = [proxy] + supportingOutbounds + [
            ["tag": "direct", "protocol": "freedom"],
            ["tag": "block", "protocol": "blackhole"],
        ]
        return configuration
    }

    private static func inbound(_ localProxy: LocalProxy) throws -> [String: Any] {
        [
            "tag": inboundTag,
            "listen": "[\(LocalProxy.host)]",
            "port": localProxy.port,
            "protocol": "socks",
            "settings": [
                "udp": true,
                "auth": "password",
                "accounts": [["user": localProxy.username, "pass": localProxy.password]],
            ] as [String: Any],
            "sniffing": try JSONSerialization.jsonObject(with: try JSONEncoder().encode(SniffingModel.current)),
        ]
    }
}
