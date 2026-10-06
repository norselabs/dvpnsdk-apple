//
//  DeviceEvent.swift
//  DVPNSDK
//

/// A state of the device that the backend revealed by refusing a request, which an app reacts to outside that request.
public enum DeviceState: Equatable, Sendable {
    /// The device token was refused (401).
    case unauthorized
    case banned
    case notEnrolled
    /// The app itself is switched off on the backend.
    case appInactive
}

/// A device state as `HTTPClient.deviceEvents()` reports it: once per request, after any mirror attempt, for requests
/// whose target reports the device's state.
public struct DeviceEvent: Equatable, Sendable {
    public let state: DeviceState
    /// The device token the refused request carried, or nil if it had none. A 401 for an older token than the stored
    /// one comes from a request sent before the token changed.
    public let sentToken: String?

    public init(state: DeviceState, sentToken: String?) {
        self.state = state
        self.sentToken = sentToken
    }
}
