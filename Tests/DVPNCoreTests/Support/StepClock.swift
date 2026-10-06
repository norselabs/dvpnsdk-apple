//
//  StepClock.swift
//  DVPNCore
//

import Synchronization

/// A clock whose sleeps return at once and move its time forward by the requested amount, so every timeout in the
/// tunnel layer elapses without real time passing.
final class StepClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let current = Mutex(Duration.zero)

    var now: Instant { Instant(offset: current.withLock { $0 }) }
    var minimumResolution: Duration { .zero }
    var elapsed: Duration { current.withLock { $0 } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        current.withLock { $0 = max($0, deadline.offset) }
    }
}
