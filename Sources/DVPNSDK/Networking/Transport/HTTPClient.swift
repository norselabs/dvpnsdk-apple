//
//  HTTPClient.swift
//  DVPNSDK
//

import Foundation

// MARK: - HTTPClient

public protocol HTTPClient: Sendable {
    /// Executes an API request.
    ///
    /// - Parameters:
    ///   - request: the API request to send.
    ///   - requestHeaders: extra headers applied to every attempt (primary and mirror).
    ///   - type: the expected response type.
    /// - Throws: `APIError`, or `CancellationError` when the caller was cancelled.
    func execute<T: Decodable & Sendable>(
        _ request: APIRequest,
        requestHeaders: [String: String],
        as type: T.Type
    ) async throws -> T

    /// Re-evaluates which endpoint to use.
    func refreshEndpoint() async

    /// The device states that refused requests reveal, as they happen (`DeviceEvent`).
    func deviceEvents() -> AsyncStream<DeviceEvent>
}

// MARK: - Convenience overload

public extension HTTPClient {
    /// No extra headers.
    func execute<T: Decodable & Sendable>(
        _ request: APIRequest,
        as type: T.Type
    ) async throws -> T {
        try await execute(request, requestHeaders: [:], as: type)
    }
}

// MARK: - DefaultHTTPClient

/// Sends requests through a transport and classifies its answers: a success is decoded, anything else becomes an
/// `APIError`, and a refusal that describes the device is also published as a `DeviceEvent`.
public final class DefaultHTTPClient: HTTPClient, Sendable {
    private let transport: any APITransport
    private let events = DeviceEventBroadcaster()

    /// Any transport: the backend's (`MirroredTransport`), or a stand-in that wraps it.
    public init(transport: any APITransport) {
        self.transport = transport
    }

    public func execute<T: Decodable & Sendable>(
        _ request: APIRequest,
        requestHeaders: [String: String],
        as type: T.Type
    ) async throws -> T {
        let response = try await transport.send(request, headers: requestHeaders)
        guard response.isSuccess else {
            let error = APIError.answer(status: response.status, body: response.body)
            if request.target.reportsDeviceState, let state = error.deviceState {
                events.send(DeviceEvent(state: state, sentToken: response.sentToken))
            }
            throw error
        }
        return try response.decoded(as: T.self)
    }

    public func refreshEndpoint() async {
        await transport.refreshEndpoint()
    }

    public func deviceEvents() -> AsyncStream<DeviceEvent> {
        events.subscribe()
    }
}
