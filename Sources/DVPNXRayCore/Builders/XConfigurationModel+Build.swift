//
//  XConfigurationModel+Build.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation

public extension XConfigurationModel {
    /// The Xray `proxy` outbound object for this model (protocol settings + stream settings).
    func proxyOutbound() throws -> [String: Any] {
        var proxy: [String: Any] = ["protocol": outbound.protocolName]
        switch outbound {
        case let .vmess(vmess):
            proxy["settings"] = ["vnext": [try jsonObject(vmess)]]
        case let .vless(vless):
            proxy["settings"] = ["vnext": [try jsonObject(vless)]]
        case let .trojan(trojan):
            proxy["settings"] = ["servers": [try jsonObject(trojan)]]
        }

        var stream: [String: Any] = [
            "network": transport.network.rawValue,
            "security": security.kind.rawValue,
        ]
        let entry = transport.streamSettingsEntry
        stream[entry.key] = try jsonObject(entry.value)
        switch security {
        case .none:
            break
        case let .tls(tls):
            stream["tlsSettings"] = try jsonObject(tls)
        case let .reality(reality):
            stream["realitySettings"] = try jsonObject(reality)
        case .autodetect:
            // An unresolved node must never reach Xray as a chain-verified config (misleading failure).
            throw XConfigurationError.unresolvedSecurity
        }
        if obfuscation.isEnabled {
            // The proxy connection is dialled through the `fragment` freedom outbound (see `supportingOutbounds()`).
            stream["sockopt"] = ["dialerProxy": XrayDocumentBuilder.fragmentTag]
        }
        proxy["streamSettings"] = stream
        return proxy
    }

    /// Outbounds the `proxy` outbound depends on: the `fragment` freedom outbound when obfuscation is on.
    /// Rendered next to `proxyOutbound()` by `XrayDocumentBuilder`.
    func supportingOutbounds() throws -> [[String: Any]] {
        switch obfuscation {
        case .none:
            return []
        case let .tlsFragment(fragment):
            return [
                [
                    "tag": XrayDocumentBuilder.fragmentTag,
                    "protocol": "freedom",
                    "settings": ["fragment": try jsonObject(fragment)],
                    "streamSettings": ["sockopt": ["tcpNoDelay": true]],
                ],
            ]
        }
    }

    /// Convenience for the extension: the complete document with this model as the proxy outbound.
    func buildConfigurationData(localProxy: LocalProxy, assetDirectory: String? = nil) throws -> Data {
        try XrayDocumentBuilder.build(
            proxyOutbound: try proxyOutbound(),
            supportingOutbounds: try supportingOutbounds(),
            localProxy: localProxy,
            assetDirectory: assetDirectory
        )
    }

    private func jsonObject(_ value: any Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: try JSONEncoder().encode(value))
    }
}
