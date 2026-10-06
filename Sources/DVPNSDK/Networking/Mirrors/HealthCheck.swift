//
//  HealthCheck.swift
//  DVPNSDK
//

import Foundation

enum HealthCheck {
    /// Whether a GET of `url` answers 2xx with `OK` in `data.status`, within `timeout`. Never throws; a cancelled caller
    /// cancels the request and gets `false`, so it checks `Task.isCancelled` before reading that as a failed probe.
    static func succeeds(url: URL, timeout: TimeInterval) async -> Bool {
        let session = URLSession(configuration: .oneShot(timeout: timeout))
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                return false
            }
            try validate(data)
            return true
        } catch {
            return false
        }
    }

    /// Validates a raw `/health` response body; the SNI-spoof path, which has its own transport, uses it directly.
    static func validate(_ data: Data) throws {
        let response = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard response.data.status.uppercased() == "OK" else {
            throw MirrorError.invalidResponse
        }
    }
}
