//
//  NEVPNManager+Ext.swift
//  DVPNCore
//

import NetworkExtension

extension NEVPNManager {
    var tunnelBundleIdentifier: String? {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol else {
            return nil
        }
        return proto.providerBundleIdentifier
    }
}
