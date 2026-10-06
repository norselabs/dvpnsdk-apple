//
//  TunnelErrorTests.swift
//  DVPNCore
//

@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing

/// Only a declined "Add VPN Configurations" prompt counts as a denied permission.
struct TunnelErrorTests {
    @Test
    func aDeclinedPromptIsAPermissionDenial() {
        let denied = NSError(domain: NEVPNErrorDomain, code: NEVPNError.Code.configurationReadWriteFailed.rawValue)
        #expect(TunnelsServiceError.addTunnelFailed(systemError: denied).isPermissionDenied)
    }

    @Test
    func otherFailuresAreNot() {
        let invalid = NSError(domain: NEVPNErrorDomain, code: NEVPNError.Code.configurationInvalid.rawValue)
        let diskFull = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)

        #expect(!TunnelsServiceError.addTunnelFailed(systemError: invalid).isPermissionDenied)
        #expect(!TunnelsServiceError.addTunnelFailed(systemError: diskFull).isPermissionDenied)
        #expect(!TunnelsServiceError.activationFailed(.handshakeTimedOut).isPermissionDenied)
        #expect(!TunnelsServiceError.emptyCredentials.isPermissionDenied)
    }
}
