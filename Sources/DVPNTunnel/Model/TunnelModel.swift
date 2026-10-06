//
//  TunnelModel.swift
//  DVPNCore
//

import DVPNCoreKit
import DVPNWireGuardCore
import Foundation
import WireGuardKit

final class TunnelModel {
    static let keyLengthInBase64 = 44

    private(set) var interfaceModel: TunnelInterfaceModel
    private(set) var peersModel: [PeersModel]

    init(tunnelConfiguration: TunnelConfiguration?) {
        interfaceModel = TunnelInterfaceModel(
            configuration: tunnelConfiguration?.interface,
            name: tunnelConfiguration?.name
        )

        var peersData = [PeersModel]()
        if let tunnelConfiguration {
            peersData = tunnelConfiguration.peers.enumerated().map { index, configuration in
                let peerData = PeersModel(index: index)
                peerData.validatedConfiguration = configuration
                return peerData
            }
        }

        peersModel = peersData

        updatePeers()
    }

    func appendEmptyPeer() {
        let peer = PeersModel(index: peersModel.count)
        peersModel.append(peer)

        updatePeers()
    }

    func deletePeer(peer: PeersModel) {
        let removedPeer = peersModel.remove(at: peer.index)
        assert(removedPeer.index == peer.index)
        for peer in peersModel[peer.index ..< peersModel.count] {
            assert(peer.index > 0)
            peer.index -= 1
        }

        updatePeers()
    }

    func save() -> Result<TunnelConfiguration, Error> {
        let interfaceSaveResult = interfaceModel.save()
        let peerSaveResults = peersModel.map { $0.save() }

        switch interfaceSaveResult {
        case let .failure(error):
            return .failure(error)

        case let .success(interfaceConfiguration):
            var peerConfigurations = [PeerConfiguration]()
            peerConfigurations.reserveCapacity(peerSaveResults.count)

            for peerSaveResult in peerSaveResults {
                switch peerSaveResult {
                case let .failure(error):
                    return .failure(error)
                case let .success(peerConfiguration):
                    peerConfigurations.append(peerConfiguration)
                }
            }

            let peerPublicKeysArray = peerConfigurations.map(\.publicKey)
            let peerPublicKeysSet = Set<PublicKey>(peerPublicKeysArray)
            if peerPublicKeysArray.count != peerPublicKeysSet.count {
                return .failure(TunnelSavingError.publicKeyDuplicated)
            }

            let tunnelConfiguration = TunnelConfiguration(
                name: interfaceConfiguration.0,
                interface: interfaceConfiguration.1,
                peers: peerConfigurations
            )

            return .success(tunnelConfiguration)
        }
    }

    func asWireGuardConfig() -> String? {
        guard case let .success(tunnelConfiguration) = save() else { return nil }
        return tunnelConfiguration.asWgQuickConfig()
    }
}

private extension TunnelModel {
    func updatePeers() {
        let numberOfPeers = peersModel.count

        for peer in peersModel {
            peer.numberOfPeers = numberOfPeers
            peer.updateExcludePrivateIPs()
        }
    }
}
