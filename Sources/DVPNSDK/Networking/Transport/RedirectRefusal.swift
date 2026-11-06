//
//  RedirectRefusal.swift
//  DVPNSDK
//

import Foundation

/// The delegate of every session the SDK makes: it follows no redirect, so a request goes only to the host it was
/// made for, with its device token, and a redirect's own answer is the answer.
final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectRefusal()

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

extension URLSession {
    /// A session that follows no redirect (`RedirectRefusal`).
    static func refusingRedirects(configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration, delegate: RedirectRefusal.shared, delegateQueue: nil)
    }
}
