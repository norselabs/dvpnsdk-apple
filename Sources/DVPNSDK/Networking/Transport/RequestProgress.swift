//
//  RequestProgress.swift
//  DVPNSDK
//

import Foundation
import Synchronization

/// Whether an endpoint has started on a request: begun its answer, or taken the request's body. URLSession says so on
/// the request's task, which this keeps as the task is created; through it the transport also cancels that one request.
/// The task shows an answer once its first bytes after the headers are in, and later still for one without a content
/// type, whose start URLSession reads to tell its type.
final class RequestProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let task = Mutex<URLSessionTask?>(nil)

    var hasStarted: Bool {
        guard let task = task.withLock({ $0 }) else { return false }
        return task.response != nil || task.countOfBytesSent > 0
    }

    /// Cancels the request: its attempt ends with `CancellationError`.
    func cancel() {
        task.withLock { $0 }?.cancel()
    }

    func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        self.task.withLock { $0 = task }
    }
}
