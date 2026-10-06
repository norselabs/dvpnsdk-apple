//
//  HandshakeProbeTests.swift
//  DVPNCore
//

@testable import DVPNTunnel
import Foundation
import Testing

struct HandshakeProbeTests {
    private let peer = """
    private_key=00
    listen_port=8686
    public_key=3b4a
    endpoint=203.0.113.10:51820
    """

    @Test
    func handshakeTimeMeansCompleted() {
        let configuration = peer + "\nlast_handshake_time_sec=1700000000\nlast_handshake_time_nsec=5\ntx_bytes=276\nrx_bytes=188\n"
        #expect(TunnelContainer.handshakeProbe(runtimeConfiguration: configuration) == .completed)
    }

    @Test
    func receivedBytesCountAsHandshake() {
        #expect(TunnelContainer.handshakeProbe(runtimeConfiguration: peer + "\nlast_handshake_time_sec=0\nrx_bytes=188\n") == .completed)
    }

    @Test
    func peerWithoutHandshakeIsPending() {
        let configuration = peer + "\nlast_handshake_time_sec=0\nlast_handshake_time_nsec=0\ntx_bytes=148\nrx_bytes=0\n"
        #expect(TunnelContainer.handshakeProbe(runtimeConfiguration: configuration) == .pending)
    }

    @Test
    func configurationWithoutPeerIsUnavailable() {
        guard case .unavailable = TunnelContainer.handshakeProbe(runtimeConfiguration: "private_key=00\nlisten_port=0\n") else {
            Issue.record("expected unavailable"); return
        }
    }
}
