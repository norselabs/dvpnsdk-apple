//
//  DeviceEventsClient.swift
//  DVPNSDK
//

import Dependencies
import Foundation

/// The device states refused requests reveal, whichever request it was: one event per request, after any mirror
/// attempt, with the device token that request carried.
public struct DeviceEventsClient: Sendable {
    public var events: @Sendable () -> AsyncStream<DeviceEvent>

    public init(events: @escaping @Sendable () -> AsyncStream<DeviceEvent>) {
        self.events = events
    }
}

// MARK: - Live

public extension DeviceEventsClient {
    /// The events `httpClient` publishes; the live value listens to the process's.
    static func live(httpClient: any HTTPClient) -> Self {
        Self(events: { httpClient.deviceEvents() })
    }
}

// MARK: - DependencyKey

extension DeviceEventsClient: DependencyKey {
    public static let liveValue = Self.live(httpClient: ProcessHTTPClient())
    public static let testValue = Self(events: unimplemented("DeviceEventsClient.events", placeholder: AsyncStream { $0.finish() }))
}

public extension DependencyValues {
    var deviceEvents: DeviceEventsClient {
        get { self[DeviceEventsClient.self] }
        set { self[DeviceEventsClient.self] = newValue }
    }
}
