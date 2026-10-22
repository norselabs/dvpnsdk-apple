//
//  MirroredTransportAttemptsTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Testing

/// `MirroredTransport.Attempts`, the rules of a request's attempts on the primary and a mirror, event by event, with the
/// primary's start as each test sets it: a stub cannot show one, so the transport's own tests cover only a silent
/// primary.
struct MirroredTransportAttemptsTests {
    struct Target: APITarget {
        var method = HTTPMethod.get
        var payload = RequestPayload.none
        var path: String { "server" }
    }

    /// Whether the primary has started, as the test says.
    private final class Start {
        var hasHappened = false
    }

    private static let body = RequestPayload.json(["name": "value"])
    private let answer = APIResponse(status: 200, body: Data(), sentToken: nil)
    private let refused = HardFailure.error(.unreachable(.cannotConnectToHost))

    private func attempts(_ target: Target = Target(), limit: TimeInterval = 60, start: Start = Start()) -> MirroredTransport.Attempts {
        MirroredTransport.Attempts(
            request: APIRequest(target: target, timeoutInterval: limit),
            silence: 5,
            primaryFailure: PrimaryFailure(),
            primaryHasStarted: { start.hasHappened }
        )
    }

    // MARK: Who can hand over

    /// A GET and a request with a body can be handed over when their limit is longer than the primary's time to start;
    /// a request that shows nothing before its answer never can.
    @Test(arguments: [
        (Target(), 60.0, true),
        (Target(method: .post, payload: body), 60, true),
        (Target(method: .post), 60, false),
        (Target(method: .delete), 60, false),
        (Target(), 5, false),
        (Target(), 3, false),
    ])
    func whoCanHandOver(target: Target, limit: TimeInterval, expected: Bool) {
        #expect(attempts(target, limit: limit).canHandOver == expected)
    }

    // MARK: A silent primary

    /// A silent primary's GET goes to a ready mirror too, and the mirror's answer, first, is the request's.
    @Test
    func aSilentPrimarysGETGoesToAReadyMirrorToo() throws {
        var attempts = attempts()

        #expect(try attempts.step(after: .silent) == .lookForMirror)
        #expect(try attempts.step(after: .mirrorReady(true)) == .askMirror)
        #expect(try attempts.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))
    }

    /// The primary's answer, first, wins the race.
    @Test
    func aPrimaryThatAnswersFirstWinsTheRace() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(true))

        #expect(try attempts.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    /// A request with a body is cancelled on the primary first; once that attempt ends, the primary counts as timed out
    /// and the request goes to the mirror.
    @Test
    func aSilentPrimarysRequestWithABodyMovesToAReadyMirror() throws {
        var attempts = attempts(Target(method: .post, payload: Self.body))
        _ = try attempts.step(after: .silent)

        #expect(try attempts.step(after: .mirrorReady(true)) == .cancelPrimary)
        #expect(try attempts.step(after: .primary(.failure(CancellationError()))) == .askMirror)
        #expect(attempts.primaryFailure.value.map(MirroredTransport.describeFailure) == "unreachable -1001")
    }

    /// A body that left as the primary was cancelled may be acted on: the request ends as a timeout, never sent twice.
    @Test
    func aBodyThatLeftAsThePrimaryWasCancelledIsNeverSentTwice() throws {
        let start = Start()
        var attempts = attempts(Target(method: .post, payload: Self.body), start: start)
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(true))

        start.hasHappened = true

        #expect(throws: APIError.unreachable(.timedOut)) { try attempts.step(after: .primary(.failure(CancellationError()))) }
    }

    /// A primary that started keeps the request, whether it started before its time was over or during the lookup.
    @Test(arguments: [Target(), Target(method: .post, payload: body)])
    func aPrimaryThatStartedKeepsTheRequest(target: Target) throws {
        let start = Start()
        start.hasHappened = true
        var startedEarly = attempts(target, start: start)
        #expect(try startedEarly.step(after: .silent) == .wait)

        let lateStart = Start()
        var startedLate = attempts(target, start: lateStart)
        _ = try startedLate.step(after: .silent)
        lateStart.hasHappened = true
        #expect(try startedLate.step(after: .mirrorReady(true)) == .wait)
    }

    /// With no mirror ready, the primary keeps the request.
    @Test
    func withoutAMirrorThePrimaryKeepsTheRequest() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)

        #expect(try attempts.step(after: .mirrorReady(false)) == .wait)
        #expect(try attempts.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    // MARK: Failures on the way

    /// A primary that fails hard during the lookup waits for it, and the fallback then takes the mirror it found.
    @Test
    func aPrimaryFailureDuringTheLookupWaitsForItsMirror() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)

        #expect(try attempts.step(after: .primary(.failure(refused))) == .wait)
        #expect(try attempts.step(after: .mirrorReady(true)) == .askMirror)
    }

    /// With no mirror found, the request ends with the primary's failure, without looking again.
    @Test
    func aPrimaryFailureDuringALookupThatFindsNoMirrorEndsTheRequest() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .primary(.failure(refused)))

        #expect(throws: HardFailure.self) { try attempts.step(after: .mirrorReady(false)) }
    }

    /// A primary that fails hard while the mirror has the GET leaves the request to the mirror.
    @Test
    func aPrimaryFailureDuringTheRaceLeavesTheRequestToTheMirror() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(true))

        #expect(try attempts.step(after: .primary(.failure(refused))) == .wait)
        #expect(try attempts.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))
    }

    /// A mirror that fails during the race leaves the request to the primary, whose hard failure then goes on to a mirror
    /// as any other.
    @Test
    func aMirrorFailureDuringTheRaceLeavesTheRequestToThePrimary() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(true))

        #expect(try attempts.step(after: .mirror(.failure(MirrorError.noHealthyMirror))) == .wait)
        #expect(try attempts.step(after: .primary(.failure(refused))) == .askMirror)
    }

    /// A hard failure before the primary's time is over goes on to a mirror at once, and the timer's end changes nothing.
    @Test
    func aPrimaryHardFailureGoesToAMirrorAtOnce() throws {
        var attempts = attempts()

        #expect(try attempts.step(after: .primary(.failure(refused))) == .askMirror)
        #expect(try attempts.step(after: .silent) == .wait)
    }
}
