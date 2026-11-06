//
//  Socks5TunnelLoop.swift
//  DVPNSDK
//

import Foundation
import os

// MARK: - Socks5TunnelLoop

/// Runs hev-socks5-tunnel's main loop on a thread of its own, and tells a loop that ended on its own from one a stop
/// ended: after the first, nothing reads the tunnel's packets any more.
final class Socks5TunnelLoop: Sendable {
    private let isStopping = OSAllocatedUnfairLock(initialState: false)

    /// Marks the loop's coming end as asked for, before the engine is stopped.
    func stop() {
        isStopping.withLock { $0 = true }
    }

    /// Runs `run`, which blocks until the loop ends and returns its exit code, so it gets a thread of its own instead
    /// of a cooperative-pool thread. Calls `endedOnItsOwn` with the code when the loop ended without `stop()`.
    func start(_ run: @escaping @Sendable () -> Int32, endedOnItsOwn: @escaping @Sendable (Int32) -> Void) {
        let thread = Thread { [isStopping] in
            let exitCode = run()
            logger.info("hev-socks5-tunnel exited with \(exitCode, privacy: .public)")
            if !isStopping.withLock({ $0 }) {
                endedOnItsOwn(exitCode)
            }
        }
        thread.name = "io.norselabs.dvpn.hev-socks5-tunnel"
        thread.qualityOfService = .userInitiated
        thread.start()
    }
}
