//
//  MirrorsBootstrapService.swift
//  DVPNSDK
//

import Foundation
import OSLog

private let log = Logger(subsystem: "com.dvpnsdk", category: "bootstrap")

/// Races the bootstrap URL list concurrently, returning the first successfully
/// decoded non-empty mirror list. Slow / unreachable URLs no longer block the
/// faster ones, so the total wall time is bounded by the fastest successful
/// response instead of the sum of all timeouts.
struct MirrorsBootstrapService: Sendable {
    let urls: [URL]
    let timeout: TimeInterval

    func fetch() async throws -> [Mirror] {
        guard !urls.isEmpty else { throw MirrorError.bootstrapFailed }

        log.debug("bootstrap racing \(urls.count) URL(s)")
        let session = URLSession(configuration: .oneShot(timeout: timeout))
        defer { session.finishTasksAndInvalidate() }

        return try await withThrowingTaskGroup(of: [Mirror]?.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let mirrors = try await Self.mirrors(from: url, on: session)
                        if mirrors.isEmpty {
                            log.debug("bootstrap \(url.absoluteString, privacy: .public) returned empty list")
                            return nil
                        }
                        log.debug("bootstrap \(url.absoluteString, privacy: .public) returned \(mirrors.count) mirror(s)")
                        return mirrors
                    } catch {
                        log.debug("bootstrap \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }

            for try await result in group {
                if let mirrors = result {
                    group.cancelAll()
                    return mirrors
                }
            }
            try Task.checkCancellation()
            log.error("bootstrap exhausted — every URL failed")
            throw MirrorError.bootstrapFailed
        }
    }

    /// The mirror list at `url`: a 2xx answer with a decodable list, or an error.
    static func mirrors(from url: URL, on session: URLSession) async throws -> [Mirror] {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw MirrorError.invalidResponse
        }
        return try JSONDecoder().decode(DataResponse<[Mirror]>.self, from: data).data
    }
}
