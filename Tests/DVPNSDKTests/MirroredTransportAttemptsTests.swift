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
    private static let mirror = MirrorResolver.Resolved.regular(host: "mirror.test")
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
        #expect(try attempts.step(after: .mirrorReady(Self.mirror)) == .askMirror)
        #expect(try attempts.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))
    }

    /// The primary's answer, first, wins the race.
    @Test
    func aPrimaryThatAnswersFirstWinsTheRace() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

        #expect(try attempts.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    /// A request with a body is cancelled on the primary first; once that attempt ends, the primary counts as timed out
    /// and the request goes to the mirror.
    @Test
    func aSilentPrimarysRequestWithABodyMovesToAReadyMirror() throws {
        var attempts = attempts(Target(method: .post, payload: Self.body))
        _ = try attempts.step(after: .silent)

        #expect(try attempts.step(after: .mirrorReady(Self.mirror)) == .cancelPrimary)
        #expect(try attempts.step(after: .primary(.failure(CancellationError()))) == .askMirror)
        #expect(attempts.primaryFailure.value.map(MirroredTransport.describeFailure) == "unreachable -1001")
    }

    /// A body that left as the primary was cancelled may be acted on: the request ends as a timeout, never sent twice.
    @Test
    func aBodyThatLeftAsThePrimaryWasCancelledIsNeverSentTwice() throws {
        let start = Start()
        var attempts = attempts(Target(method: .post, payload: Self.body), start: start)
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

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
        #expect(try startedLate.step(after: .mirrorReady(Self.mirror)) == .wait)
    }

    /// With no mirror ready, the primary keeps the request.
    @Test
    func withoutAMirrorThePrimaryKeepsTheRequest() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)

        #expect(try attempts.step(after: .mirrorReady(nil)) == .wait)
        #expect(try attempts.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    // MARK: Failures on the way

    /// A primary that fails hard during the lookup waits for it, and the fallback then takes the mirror it found.
    @Test
    func aPrimaryFailureDuringTheLookupWaitsForItsMirror() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)

        #expect(try attempts.step(after: .primary(.failure(refused))) == .wait)
        #expect(try attempts.step(after: .mirrorReady(Self.mirror)) == .askMirror)
    }

    /// With no mirror found, the request ends with the primary's failure, without looking again.
    @Test
    func aPrimaryFailureDuringALookupThatFindsNoMirrorEndsTheRequest() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .primary(.failure(refused)))

        #expect(throws: HardFailure.self) { try attempts.step(after: .mirrorReady(nil)) }
    }

    /// A primary that fails hard while the mirror has the GET leaves the request to the mirror.
    @Test
    func aPrimaryFailureDuringTheRaceLeavesTheRequestToTheMirror() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

        #expect(try attempts.step(after: .primary(.failure(refused))) == .wait)
        #expect(try attempts.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))
    }

    /// A mirror that fails during the race leaves the request to the primary, whose hard failure then goes on to a mirror
    /// as any other.
    @Test
    func aMirrorFailureDuringTheRaceLeavesTheRequestToThePrimary() throws {
        var attempts = attempts()
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

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

// MARK: - A silent preferred mirror

/// `MirroredTransport.MirrorFirstAttempts`, the same rules the other way round: a request on its preferred mirror and
/// the primary, with each send's start as the test marks it on its progress.
extension MirroredTransportAttemptsTests {
    private func mirrorFirst(_ target: Target = Target(), limit: TimeInterval = 60) -> MirroredTransport.MirrorFirstAttempts {
        MirroredTransport.MirrorFirstAttempts(
            request: APIRequest(target: target, timeoutInterval: limit),
            silence: 5,
            primaryFailure: PrimaryFailure()
        )
    }

    /// A silent mirror gives up the requests a silent primary gives up: a GET or one with a body, whose limit is longer
    /// than the time to start.
    @Test
    func whoCanLeaveASilentMirror() {
        #expect(mirrorFirst().canHandOver)
        #expect(mirrorFirst(Target(method: .post, payload: Self.body)).canHandOver)
        #expect(!mirrorFirst(Target(method: .delete)).canHandOver)
        #expect(!mirrorFirst(limit: 5).canHandOver)
    }

    /// The mirror looked up is asked, and its answer is the request's.
    @Test
    func theMirrorFoundIsAsked() throws {
        var attempts = mirrorFirst()

        #expect(try attempts.step(after: .mirrorReady(Self.mirror)) == .askMirror(Self.mirror))
        #expect(try attempts.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))
        #expect(!attempts.hasFoundNoMirror)
    }

    /// A silent mirror's GET goes to the primary too, and the first answer wins.
    @Test
    func aSilentMirrorsGETGoesToThePrimaryToo() throws {
        var primaryFirst = mirrorFirst()
        _ = try primaryFirst.step(after: .mirrorReady(Self.mirror))
        #expect(try primaryFirst.step(after: .silent) == .askPrimary)
        #expect(try primaryFirst.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))

        var mirrorFirst = mirrorFirst()
        _ = try mirrorFirst.step(after: .mirrorReady(Self.mirror))
        _ = try mirrorFirst.step(after: .silent)
        #expect(try mirrorFirst.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))
    }

    /// A silent mirror's request with a body is stopped first; its stopped send's end hands the request to the primary.
    @Test
    func aSilentMirrorsRequestWithABodyIsStoppedForThePrimary() throws {
        var attempts = mirrorFirst(Target(method: .post, payload: Self.body))
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

        #expect(try attempts.step(after: .silent) == .stopMirror)
        #expect(try attempts.step(after: .mirror(.failure(CancellationError()))) == .askPrimary)
        #expect(try attempts.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    /// A body that left as the mirror was stopped may be acted on: the request ends as a timeout, never sent twice,
    /// however the stopped send ended.
    @Test(arguments: [CancellationError() as any Error, HardFailure.error(.unreachable(.networkConnectionLost))])
    func aBodyThatLeftAsTheMirrorWasStoppedIsNeverSentTwice(end: any Error) throws {
        var attempts = mirrorFirst(Target(method: .post, payload: Self.body))
        _ = try attempts.step(after: .mirrorReady(Self.mirror))
        _ = try attempts.step(after: .silent)

        attempts.mirrorProgress.markStarted()

        #expect(throws: APIError.unreachable(.timedOut)) { try attempts.step(after: .mirror(.failure(end))) }
    }

    /// A mirror that started keeps the request.
    @Test(arguments: [Target(), Target(method: .post, payload: body)])
    func aMirrorThatStartedKeepsTheRequest(target: Target) throws {
        var attempts = mirrorFirst(target)
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

        attempts.mirrorProgress.markStarted()

        #expect(try attempts.step(after: .silent) == .wait)
    }

    /// A mirror still being looked up when the time is over: a GET goes to the primary too, and the mirror found later
    /// is asked as well.
    @Test
    func aGETWhoseMirrorIsStillLookedUpGoesToThePrimaryToo() throws {
        var attempts = mirrorFirst()

        #expect(try attempts.step(after: .silent) == .askPrimary)
        #expect(try attempts.step(after: .mirrorReady(Self.mirror)) == .askMirror(Self.mirror))
    }

    /// A request with a body whose mirror is still being looked up goes to the primary. The mirror found later waits,
    /// and takes the request only if the primary fails before taking it: the mirror never had it.
    @Test
    func aBodyWhoseMirrorIsStillLookedUpGoesToThePrimaryAndBackOnlyIfItFailsFirst() throws {
        var found = mirrorFirst(Target(method: .post, payload: Self.body))
        #expect(try found.step(after: .silent) == .askPrimary)
        #expect(try found.step(after: .mirrorReady(Self.mirror)) == .wait)
        #expect(try found.step(after: .primary(.failure(refused))) == .askMirror(Self.mirror))
        #expect(try found.step(after: .mirror(.success(answer))) == .answer(answer, fromMirror: true))

        var stillLookingUp = mirrorFirst(Target(method: .post, payload: Self.body))
        _ = try stillLookingUp.step(after: .silent)
        #expect(try stillLookingUp.step(after: .primary(.failure(refused))) == .wait)
        #expect(try stillLookingUp.step(after: .mirrorReady(Self.mirror)) == .askMirror(Self.mirror))

        var noMirror = mirrorFirst(Target(method: .post, payload: Self.body))
        _ = try noMirror.step(after: .silent)
        _ = try noMirror.step(after: .primary(.failure(refused)))
        #expect(throws: HardFailure.self) { try noMirror.step(after: .mirrorReady(nil)) }
    }

    /// A primary that took the body may be acting on it: its failure is the request's, and the mirror never has it.
    @Test
    func aBodyThePrimaryTookNeverGoesBackToTheMirror() throws {
        var attempts = mirrorFirst(Target(method: .post, payload: Self.body))
        _ = try attempts.step(after: .silent)
        _ = try attempts.step(after: .mirrorReady(Self.mirror))

        attempts.primaryProgress.markStarted()

        #expect(throws: HardFailure.self) { try attempts.step(after: .primary(.failure(refused))) }
    }

    /// A mirror that fails hard gives way to one more, looked up without it, whose failure is the request's unless the
    /// primary has the request too. A GET's start on the first counts for nothing once it failed.
    @Test
    func aMirrorThatFailsHardGivesWayToOneMore() throws {
        let another = MirrorResolver.Resolved.regular(host: "another.test")
        var alone = mirrorFirst()
        _ = try alone.step(after: .mirrorReady(Self.mirror))
        #expect(try alone.step(after: .mirror(.failure(refused))) == .lookForMirror(dropping: Self.mirror))
        #expect(try alone.step(after: .mirrorReady(another)) == .askMirror(another))
        #expect(throws: HardFailure.self) { try alone.step(after: .mirror(.failure(refused))) }

        var racing = mirrorFirst()
        _ = try racing.step(after: .mirrorReady(Self.mirror))
        racing.mirrorProgress.markStarted()
        _ = try racing.step(after: .mirror(.failure(refused)))
        #expect(try racing.step(after: .silent) == .askPrimary)
        _ = try racing.step(after: .mirrorReady(another))
        #expect(try racing.step(after: .mirror(.failure(refused))) == .wait)
        #expect(try racing.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    /// With no mirror found or answering, the primary takes the request, and later requests go to it.
    @Test
    func withoutAMirrorThePrimaryTakesTheRequest() throws {
        var notFound = mirrorFirst()
        #expect(try notFound.step(after: .mirrorReady(nil)) == .askPrimary)
        #expect(notFound.hasFoundNoMirror)
        #expect(try notFound.step(after: .silent) == .wait)

        var notAnswering = mirrorFirst()
        _ = try notAnswering.step(after: .mirrorReady(Self.mirror))
        _ = try notAnswering.step(after: .mirror(.failure(refused)))
        _ = try notAnswering.step(after: .mirrorReady(Self.mirror))
        let unreachable = SNISpoofTransport.TransportError.connectionFailed(URLError(.timedOut))
        #expect(try notAnswering.step(after: .mirror(.failure(unreachable))) == .askPrimary)
        #expect(notAnswering.hasFoundNoMirror)
    }

    /// A mirror's failure that is not hard is the request's, as before, unless the primary has the request too.
    @Test
    func aMirrorsOtherFailureIsTheRequestsUnlessThePrimaryHasIt() throws {
        let invalid = APIError.invalidResponse(status: 0)
        var alone = mirrorFirst()
        _ = try alone.step(after: .mirrorReady(Self.mirror))
        #expect(throws: APIError.invalidResponse(status: 0)) { try alone.step(after: .mirror(.failure(invalid))) }

        var racing = mirrorFirst()
        _ = try racing.step(after: .mirrorReady(Self.mirror))
        _ = try racing.step(after: .silent)
        #expect(try racing.step(after: .mirror(.failure(invalid))) == .wait)
        #expect(try racing.step(after: .primary(.success(answer))) == .answer(answer, fromMirror: false))
    }

    /// When both fail, the request ends with the primary's failure, which says more; the deadline has it too, also when
    /// it is not a hard one.
    @Test
    func whenBothFailThePrimarysFailureIsTheRequests() throws {
        var attempts = mirrorFirst()
        _ = try attempts.step(after: .mirrorReady(Self.mirror))
        _ = try attempts.step(after: .silent)

        let badAnswer = APIError.unreachable(.badServerResponse)
        #expect(try attempts.step(after: .primary(.failure(badAnswer))) == .wait)
        #expect(attempts.primaryFailure.value.map(MirroredTransport.describeFailure) == "unreachable -1011")
        _ = try attempts.step(after: .mirror(.failure(refused)))
        #expect(throws: APIError.unreachable(.badServerResponse)) { try attempts.step(after: .mirrorReady(nil)) }
    }
}
