//
//  RequestProgress.swift
//  DVPNSDK
//

import Foundation
import Synchronization

/// Whether an endpoint has started on one send of a request: begun its answer, or taken the request's body. URLSession
/// says so on the send's task, which this keeps as the task is created; an SNI mirror's send says so itself
/// (`markStarted(_:)`). The task shows an answer once its first bytes after the headers are in, and later still for one
/// without a content type, whose start URLSession reads to tell its type. `cancel()` stops the send, also one that has
/// not begun yet: its attempt ends with a `CancellationError`.
final class RequestProgress: NSObject, URLSessionTaskDelegate, Sendable {
    /// How far an endpoint has got on the send: an answer begun is further than a body taken.
    enum Start: Comparable {
        /// It took the request's body, and has not begun its answer.
        case body
        case answer
    }

    private struct State {
        var isCancelled = false
        /// The send's task, once URLSession has created it.
        var task: URLSessionTask?
        /// Stops the send's own connection (an SNI mirror's).
        var stop: (@Sendable () -> Void)?
        /// How far the send said it got (an SNI mirror's).
        var markedStart: Start?
    }

    private let state = Mutex(State())

    var start: Start? {
        state.withLock { state in
            if let markedStart = state.markedStart { return markedStart }
            guard let task = state.task else { return nil }
            if task.response != nil { return .answer }
            return task.countOfBytesSent > 0 ? .body : nil
        }
    }

    var hasStarted: Bool {
        start != nil
    }

    /// The send was stopped: one that has not begun must not.
    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    func cancel() {
        let (task, stop) = state.withLock { state in
            state.isCancelled = true
            return (state.task, state.stop)
        }
        task?.cancel()
        stop?()
    }

    /// The send's own connection, which `cancel()` stops: at once when the send was stopped already.
    func attach(stop: @escaping @Sendable () -> Void) {
        let isCancelled = state.withLock { state in
            state.stop = stop
            return state.isCancelled
        }
        if isCancelled { stop() }
    }

    /// The send started: its body left, or its answer began. A later body never takes an answer begun back.
    func markStarted(_ start: Start) {
        state.withLock { state in
            state.markedStart = max(start, state.markedStart ?? start)
        }
    }

    func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        let isCancelled = state.withLock { state in
            state.task = task
            return state.isCancelled
        }
        if isCancelled { task.cancel() }
    }
}
