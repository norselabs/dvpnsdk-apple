//
//  EventBroadcaster.swift
//  DVPNCore
//

import Foundation

/// Fan-out of one event source to any number of `AsyncStream` consumers.
/// New subscribers immediately receive the latest remembered event, so status waits can never miss a
/// transition. One-shot events (errors) are sent with `remember: false` so they are not replayed to
/// every later subscriber.
/// `@unchecked`: the subscriber table and the remembered event are only touched under the lock.
final class EventBroadcaster<Event: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var latest: Event?

    init(initial: Event? = nil) {
        latest = initial
    }

    var current: Event? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func subscribe() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let replay = latest
            lock.unlock()

            if let replay {
                continuation.yield(replay)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    func send(_ event: Event, remember: Bool = true) {
        lock.lock()
        if remember { latest = event }
        let targets = Array(continuations.values)
        lock.unlock()
        targets.forEach { $0.yield(event) }
    }
}
