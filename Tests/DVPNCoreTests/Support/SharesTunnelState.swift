//
//  SharesTunnelState.swift
//  DVPNSDK
//

import Testing

// MARK: - SharesTunnelState

/// For a suite whose tests use the tunnel layer's process-wide state: `DVPNCore.bootstrap`'s one configuration, and the
/// App Group defaults (`NodeAddressStore`, `ProxyStartErrorStore`, `TunnelStateStore`). The suite runs whole while no
/// other suite with the trait runs, so their tests never interleave; `.serialized` orders a suite's own tests.
struct SharesTunnelState: SuiteTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await TunnelStateLock.shared.acquire()
        do {
            try await function()
        } catch {
            await TunnelStateLock.shared.release()
            throw error
        }
        await TunnelStateLock.shared.release()
    }
}

extension Trait where Self == SharesTunnelState {
    static var sharesTunnelState: Self { Self() }
}

// MARK: - TunnelStateLock

/// One test at a time, in the order they asked.
private actor TunnelStateLock {
    static let shared = TunnelStateLock()

    private var isHeld = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        guard !waiting.isEmpty else {
            isHeld = false
            return
        }
        waiting.removeFirst().resume()
    }
}
