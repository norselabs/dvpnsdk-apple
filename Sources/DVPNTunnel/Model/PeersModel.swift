//
//  PeersModel.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation
import WireGuardKitTypes

enum PeerField: CaseIterable {
    case publicKey
    case preSharedKey
    case endpoint
    case persistentKeepAlive
    case allowedIPs
}

/// One peer of the WireGuard configuration the tunnel manager fills in field by field and validates with `save()`.
final class PeersModel {
    var index: Int
    private var data = [PeerField: String]()
    var validatedConfiguration: PeerConfiguration?

    init(index: Int) {
        self.index = index
    }

    subscript(field: PeerField) -> String {
        get {
            if data.isEmpty { fillData() }
            return data[field] ?? ""
        }
        set(stringValue) {
            if data.isEmpty { fillData() }
            validatedConfiguration = nil
            if stringValue.isEmpty {
                data.removeValue(forKey: field)
            } else {
                data[field] = stringValue
            }
        }
    }

    // One branch per peer field being validated.
    // swiftlint:disable:next cyclomatic_complexity
    func save() -> Result<PeerConfiguration, Error> {
        if let validatedConfiguration { return .success(validatedConfiguration) }

        guard let publicKeyString = data[.publicKey] else {
            return .failure(TunnelSavingError.publicKeyRequired)
        }
        guard let publicKey = PublicKey(base64Key: publicKeyString) else {
            return .failure(TunnelSavingError.publicKeyInvalid)
        }

        var config = PeerConfiguration(publicKey: publicKey)

        if let preSharedKeyString = data[.preSharedKey] {
            guard let preSharedKey = PreSharedKey(base64Key: preSharedKeyString) else {
                return .failure(TunnelSavingError.preSharedKeyInvalid)
            }
            config.preSharedKey = preSharedKey
        }

        if let allowedIPsString = data[.allowedIPs] {
            let allowedIPs = allowedIPsString
                .splitToArray(trimmingCharacters: .whitespacesAndNewlines)
                .map { IPAddressRange(from: $0) }
            if allowedIPs.contains(nil) {
                return .failure(TunnelSavingError.allowedIPsInvalid)
            }
            config.allowedIPs = allowedIPs.compactMap(\.self)
        }

        if let endpointString = data[.endpoint] {
            guard let endpoint = Endpoint(from: endpointString) else {
                return .failure(TunnelSavingError.endpointInvalid)
            }
            config.endpoint = endpoint
        }

        if let persistentKeepAliveString = data[.persistentKeepAlive], !persistentKeepAliveString.isEmpty {
            // The kit stores the interval as text (AmneziaWG allows ranges); this form only produces plain seconds.
            guard UInt16(persistentKeepAliveString) != nil else {
                return .failure(TunnelSavingError.persistentKeepAliveInvalid)
            }
            config.persistentKeepAlive = persistentKeepAliveString
        }

        validatedConfiguration = config
        return .success(config)
    }
}

private extension PeersModel {
    func fillData() {
        guard let config = validatedConfiguration else { return }
        var data = [PeerField: String]()
        data[.publicKey] = config.publicKey.base64Key
        if let preSharedKey = config.preSharedKey?.base64Key {
            data[.preSharedKey] = preSharedKey
        }
        if !config.allowedIPs.isEmpty {
            data[.allowedIPs] = config.allowedIPs.map(\.stringRepresentation).joined(separator: ", ")
        }
        if let endpoint = config.endpoint {
            data[.endpoint] = endpoint.stringRepresentation
        }
        if let persistentKeepAlive = config.persistentKeepAlive {
            data[.persistentKeepAlive] = String(persistentKeepAlive)
        }
        self.data = data
    }
}
