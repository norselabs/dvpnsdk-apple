//
//  DeviceEventBroadcaster.swift
//  DVPNSDK
//

import Foundation
import Synchronization

/// Hands each device event to every current subscriber; a later subscriber gets only later events.
final class DeviceEventBroadcaster: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<DeviceEvent>.Continuation]>([:])

    func subscribe() -> AsyncStream<DeviceEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.continuations.withLock { $0[id] = nil }
            }
        }
    }

    func send(_ event: DeviceEvent) {
        let targets = continuations.withLock { Array($0.values) }
        targets.forEach { $0.yield(event) }
    }
}
