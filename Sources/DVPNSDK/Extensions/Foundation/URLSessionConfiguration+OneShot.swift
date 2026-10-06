//
//  URLSessionConfiguration+OneShot.swift
//  DVPNSDK
//

import Foundation

extension URLSessionConfiguration {
    /// For a session that sends one probe or one list request and is then invalidated: ephemeral, no cache, `timeout`
    /// for the request and the whole resource.
    static func oneShot(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }
}
