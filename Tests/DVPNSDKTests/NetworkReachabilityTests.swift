//
//  NetworkReachabilityTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Network
import Testing

/// The status is unknown until the monitor's first report: a read before it waits for the report instead of reading
/// "offline", and gives up on a monitor that never reports.
struct NetworkReachabilityTests {
    private func makeReachability(
        firstStatusWait: Duration = .seconds(5)
    ) -> (NetworkReachability, AsyncStream<NWPath.Status>.Continuation) {
        let (statuses, reports) = AsyncStream.makeStream(of: NWPath.Status.self)
        return (NetworkReachability(statuses: statuses, firstStatusWait: firstStatusWait), reports)
    }

    /// The report that says "offline" arrives after the read started: the read still gets it, not an unknown status.
    @Test
    func aReadBeforeTheFirstReportWaitsForIt() async throws {
        let (reachability, reports) = makeReachability()

        async let reachable = reachability.isReachable
        try await Task.sleep(for: .milliseconds(30))
        reports.yield(.unsatisfied)

        #expect(await !reachable)
    }

    @Test
    func aSatisfiedPathIsReachable() async {
        let (reachability, reports) = makeReachability()
        reports.yield(.satisfied)

        #expect(await reachability.isReachable)
    }

    /// A path that needs a connection to be attached is not reachable yet, as before.
    @Test(arguments: [NWPath.Status.unsatisfied, .requiresConnection])
    func aPathThatIsNotSatisfiedIsNotReachable(status: NWPath.Status) async {
        let (reachability, reports) = makeReachability()
        reports.yield(status)

        #expect(await !reachability.isReachable)
    }

    /// A monitor that never reports is not the network's fault: the request goes through and fails on its own, and
    /// only the first read pays the wait.
    @Test
    func aMonitorThatNeverReportsLetsTheRequestThroughAndIsNotWaitedForAgain() async {
        let (reachability, _) = makeReachability(firstStatusWait: .milliseconds(100))

        #expect(await reachability.isReachable)
        #expect(await reachability.hasGivenUpWaiting)
        #expect(await reachability.isReachable)
    }

    /// One consumer applies the reports in order, so the last one stands (each used to hop through its own task).
    @Test
    func reportsAreAppliedInOrder() async {
        let (reachability, reports) = makeReachability()
        for status in [NWPath.Status.satisfied, .unsatisfied, .satisfied, .unsatisfied] {
            reports.yield(status)
        }
        reports.finish()
        await reachability.untilReportsEnd()

        #expect(await !reachability.isReachable)
    }

    @Test
    func aLaterReportReplacesTheStatus() async {
        let (reachability, reports) = makeReachability()
        reports.yield(.unsatisfied)
        #expect(await !reachability.isReachable)

        reports.yield(.satisfied)
        reports.finish()
        await reachability.untilReportsEnd()

        #expect(await reachability.isReachable)
    }
}
