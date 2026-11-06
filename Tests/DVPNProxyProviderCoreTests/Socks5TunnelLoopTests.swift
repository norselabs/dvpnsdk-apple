//
//  Socks5TunnelLoopTests.swift
//  DVPNSDK
//

@testable import DVPNProxyProviderCore
import os
import Testing

/// A hev-socks5-tunnel loop that ends on its own is reported, so the provider cancels the tunnel instead of staying
/// connected with nothing reading its packets; one a stop ended is not. The provider itself cannot be made outside an
/// extension (its initializer gives nil), so the tests drive its loop.
@Suite(.timeLimit(.minutes(1)))
struct Socks5TunnelLoopTests {
    @Test
    func aLoopThatEndsOnItsOwnIsReported() async throws {
        let loop = Socks5TunnelLoop()
        let ends = Ends()

        loop.start { 1 } endedOnItsOwn: { ends.record($0) }

        try await ends.wait()
        #expect(ends.exitCodes == [1])
    }

    @Test
    func aLoopAStopEndsIsNotReported() async throws {
        let loop = Socks5TunnelLoop()
        let ends = Ends()

        loop.stop()
        loop.start { 0 } endedOnItsOwn: { ends.record($0) }

        try await ends.wait()
        #expect(ends.exitCodes.isEmpty)
    }
}

/// The exit codes the loop reported. Waits for one, 2 s at most: the loop's thread reports at once after `run`
/// returns, so a test that expects none waits the full time.
private final class Ends: Sendable {
    private let reported = OSAllocatedUnfairLock<[Int32]>(initialState: [])

    var exitCodes: [Int32] {
        reported.withLock { $0 }
    }

    func record(_ exitCode: Int32) {
        reported.withLock { $0.append(exitCode) }
    }

    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline, exitCodes.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
