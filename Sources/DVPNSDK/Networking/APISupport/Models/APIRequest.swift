//
//  APIRequest.swift
//  DVPNSDK
//

import Foundation

/// A request to the backend, whichever endpoint it goes to: the transport puts the target's path on the API's URL or a
/// mirror's.
public struct APIRequest: Sendable {
    public let target: any APITarget
    public let timeoutInterval: TimeInterval
    /// Send over a brand-new connection instead of the shared session's pool. Needed for answers that
    /// depend on the client's network path (`/ip`): a pooled connection opened before a VPN tunnel came
    /// up keeps its original route, so reusing it reports the pre-tunnel address.
    public let requiresFreshConnection: Bool

    public init(target: any APITarget, timeoutInterval: TimeInterval = RequestTimeout.standard, requiresFreshConnection: Bool = false) {
        self.target = target
        self.timeoutInterval = timeoutInterval
        self.requiresFreshConnection = requiresFreshConnection
    }
}

extension APIRequest {
    /// The `URLRequest` for the target on `baseURL`: path, method, query or JSON body, no caching.
    func urlRequest(baseURL: URL) throws -> URLRequest {
        var url = target.path.isEmpty ? baseURL : baseURL.appendingPathComponent(target.path)

        if case let .query(items) = target.payload, !items.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
            components.queryItems = (components.queryItems ?? []) + items.sorted { $0.name < $1.name }
            guard let withQuery = components.url else { throw URLError(.badURL) }
            url = withQuery
        }

        var request = URLRequest(url: url)
        request.httpMethod = target.method.rawValue
        request.timeoutInterval = timeoutInterval
        // API answers are never served from the HTTP cache: they describe live state (IP, servers, credentials).
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if case let .json(body) = target.payload {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }
}
