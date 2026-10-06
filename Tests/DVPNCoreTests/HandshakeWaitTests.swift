//
//  HandshakeWaitTests.swift
//  DVPNCore
//

import DVPNCoreKit
@testable import DVPNTunnel
import Foundation
import NetworkExtension
import Testing

/// The WireGuard handshake wait runs on the injected clock, deadline included.
@MainActor
struct HandshakeWaitTests {
    init() {
        DVPNCore.bootstrap(
            DVPNCoreConfiguration(
                appGroupID: "group.com.example.vpn.tests",
                protocols: [
                    TunnelProtocolDescriptor(
                        id: .wireGuard, providerBundleID: "com.example.vpn.wireguard-ne", tunnelName: "WireGuard", readiness: .wireGuardHandshake
                    ),
                    TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.v2ray-ne", tunnelName: "Xray", readiness: .immediate),
                ]
            )
        )
    }

    /// A connected tunnel whose handshake cannot be observed (no provider session) is polled until the deadline.
    /// On a clock that returns from every sleep at once, that deadline must not be the wall clock's 10 s.
    @Test
    func anImmediateClockEndsTheWaitWithoutRealTimePassing() async {
        let clock = StepClock()
        let tunnel = TunnelContainer(tunnel: NETunnelProviderManager(), clock: clock)
        tunnel.status = .connected

        let started = ContinuousClock.now
        let readiness = await tunnel.readiness(timeout: .seconds(10))

        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(clock.elapsed >= .seconds(10))
        guard case .unavailable = readiness else {
            Issue.record("expected an unobservable handshake, got \(readiness)")
            return
        }
    }
}
