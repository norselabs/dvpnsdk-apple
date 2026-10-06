//
//  NetworkReachability.swift
//  DVPNSDK
//

import Foundation
import Network

/// Whether the device has a network path. The system reports the first path a couple of milliseconds after the monitor
/// starts, and the client is created by the request that needs it: until that report the status is unknown, and
/// reading it as "not reachable" failed the launch's first requests as offline without trying.
actor NetworkReachability {
    private static let queue = DispatchQueue(label: "com.dvpnsdk.reachability")

    /// The latest report; nil until the first one.
    private var status: NWPath.Status?
    private let firstStatusWait: Duration
    /// Set once a read has waited the whole bound for a first report that never came, so later reads do not wait again.
    private(set) var hasGivenUpWaiting = false
    /// Reads waiting for the first report; it resumes them, and so does each one's own cancellation.
    private var firstReportWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Written once in `init`, cancelled in `deinit`; cancelling ends the stream and with it the monitor.
    private nonisolated(unsafe) var consumer: Task<Void, Never>?

    /// `statuses` are the monitor's reports in order, applied by one consumer so a quick change cannot be overtaken.
    /// `firstStatusWait` bounds how long a read waits for the first.
    init(
        statuses: AsyncStream<NWPath.Status> = NetworkReachability.monitoredStatuses(),
        firstStatusWait: Duration = .seconds(1)
    ) {
        self.firstStatusWait = firstStatusWait
        consumer = Task { [weak self] in
            for await status in statuses {
                guard let self else { return }
                await setStatus(status)
            }
        }
    }

    deinit {
        consumer?.cancel()
    }

    /// Whether a request should be tried. A known status decides: only a satisfied path is reachable. An unknown one
    /// waits for the first report and, if none comes within the bound, lets the request through: its own failure
    /// says whether the network is there.
    var isReachable: Bool {
        get async {
            await waitForFirstStatus()
            return status.map { $0 == .satisfied } ?? true
        }
    }

    private func setStatus(_ status: NWPath.Status) {
        self.status = status
        let waiters = firstReportWaiters.values
        firstReportWaiters = [:]
        waiters.forEach { $0.resume() }
    }

    /// Waits for the first report, but no longer than the bound: whichever comes first ends the wait.
    private func waitForFirstStatus() async {
        guard status == nil, !hasGivenUpWaiting else { return }
        let bound = firstStatusWait
        let wasReported = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.firstReport()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: bound)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !wasReported, status == nil, !Task.isCancelled { hasGivenUpWaiting = true }
    }

    /// Returns once a status is known, or once the waiting task is cancelled.
    private func firstReport() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if status != nil || Task.isCancelled {
                    continuation.resume()
                } else {
                    firstReportWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.endWait(id) }
        }
    }

    private func endWait(_ id: UUID) {
        firstReportWaiters.removeValue(forKey: id)?.resume()
    }

    /// Returns once the reports have ended and every one is applied. For tests, which end the stream they feed.
    func untilReportsEnd() async {
        await consumer?.value
    }

    /// The system's path reports: the current one when the monitor starts, then every change.
    static func monitoredStatuses() -> AsyncStream<NWPath.Status> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: queue)
        }
    }
}
