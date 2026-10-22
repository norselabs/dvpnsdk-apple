//
//  MirroredTransport+Attempts.swift
//  DVPNSDK
//

import Foundation
import OSLog

private let log = Logger.sdk(category: "http")

// MARK: - Attempts

extension MirroredTransport {
    /// What happened while a request was with the primary and a mirror, in either order.
    enum Event: Sendable {
        /// The primary's answer, or why there is none.
        case primary(Result<APIResponse, any Error>)
        /// The time the first endpoint gets to start on the request is over.
        case silent
        /// The search for a mirror ended, with the one it found or none.
        case mirrorReady(MirrorResolver.Resolved?)
        /// The mirror's answer, or why there is none.
        case mirror(Result<APIResponse, any Error>)
    }

    /// What `sendViaPrimaryThenMirror` does next.
    enum Step: Equatable {
        /// The request ends with this answer, the mirror's when `fromMirror`.
        case answer(APIResponse, fromMirror: Bool)
        case lookForMirror
        case askMirror
        case cancelPrimary
        case wait
    }

    /// A request's attempts on the primary and a mirror: the next step after each event, by the rules of
    /// `sendViaPrimaryThenMirror`, logged. A cancelled request never gets here: the loop ends it first, so a
    /// `CancellationError` here is the transport's own cancel of a silent primary.
    struct Attempts {
        let request: APIRequest
        let silence: TimeInterval
        let primaryFailure: PrimaryFailure
        /// Whether the primary has started on the request (`RequestProgress.hasStarted`).
        let primaryHasStarted: () -> Bool
        var primaryHardFailure: HardFailure?
        /// A mirror is being looked up for a silent primary.
        var isLookingForMirror = false
        /// A mirror has the request now.
        var isMirrorAsked = false
        /// The primary was cancelled for a mirror.
        var isHandingOver = false

        var path: String { request.target.loggedPath }

        /// Whether a silent primary can hand this request over at all.
        var canHandOver: Bool { request.canBeHandedOver && silence < request.timeoutInterval }

        mutating func step(after event: Event) throws -> Step {
            switch event {
            case let .primary(.success(response)):
                let path = path
                log.debug("send [\(path, privacy: .public)] primary answered \(response.status)")
                return .answer(response, fromMirror: false)
            case let .primary(.failure(error)):
                return try stepAfterPrimaryFailure(error)
            case .silent:
                return stepAfterSilence()
            case let .mirrorReady(route):
                return try stepAfterLookup(foundMirror: route != nil)
            case let .mirror(.success(response)):
                return .answer(response, fromMirror: true)
            case let .mirror(.failure(error)):
                return try stepAfterMirrorFailure(error)
            }
        }

        private mutating func stepAfterPrimaryFailure(_ error: any Error) throws -> Step {
            let path = path
            let failure = try hardFailure(of: error)
            let described = MirroredTransport.describeFailure(failure)
            primaryFailure.set(failure)
            primaryHardFailure = failure
            if isMirrorAsked {
                log.notice("send [\(path, privacy: .public)] primary hard-failed (\(described, privacy: .public)) — waiting for the mirror")
                return .wait
            }
            if isLookingForMirror {
                log.notice("send [\(path, privacy: .public)] primary hard-failed (\(described, privacy: .public)) — falling back to the mirror being looked up")
                return .wait
            }
            log.notice("send [\(path, privacy: .public)] primary hard-failed (\(described, privacy: .public)) — falling back to mirror")
            isMirrorAsked = true
            return .askMirror
        }

        private mutating func stepAfterSilence() -> Step {
            let path = path
            let silence = silence
            guard !isMirrorAsked else { return .wait }
            guard !primaryHasStarted() else {
                log.debug("send [\(path, privacy: .public)] primary started — waiting for its answer")
                return .wait
            }
            log.notice("send [\(path, privacy: .public)] primary silent for \(silence) s — looking for a mirror")
            isLookingForMirror = true
            return .lookForMirror
        }

        private mutating func stepAfterLookup(foundMirror: Bool) throws -> Step {
            let path = path
            isLookingForMirror = false
            // The primary failed during the lookup: the fallback takes the mirror it found, and with none, the primary's
            // failure says more than "no healthy mirror". One lookup a request, as when the primary fails at once.
            if let primaryHardFailure {
                guard foundMirror else {
                    log.error("send [\(path, privacy: .public)] no mirror answered (none found)")
                    throw primaryHardFailure
                }
                isMirrorAsked = true
                return .askMirror
            }
            guard foundMirror, !primaryHasStarted() else {
                log.debug("send [\(path, privacy: .public)] no mirror to take over, or the primary started — waiting for the primary")
                return .wait
            }
            if request.target.method == .get {
                log.notice("send [\(path, privacy: .public)] primary still silent — asking the mirror too")
                isMirrorAsked = true
                return .askMirror
            }
            log.notice("send [\(path, privacy: .public)] primary still silent — handing the request over to the mirror")
            isHandingOver = true
            return .cancelPrimary
        }

        private mutating func stepAfterMirrorFailure(_ error: any Error) throws -> Step {
            let path = path
            let described = MirroredTransport.describeFailure(error)
            isMirrorAsked = false
            guard let primaryHardFailure else {
                log.notice("send [\(path, privacy: .public)] mirror failed (\(described, privacy: .public)) — waiting for the primary")
                return .wait
            }
            guard MirroredTransport.isNoMirrorAnswer(error) else { throw error }
            // The primary's failure says more than "no healthy mirror".
            log.error("send [\(path, privacy: .public)] no mirror answered (\(described, privacy: .public))")
            throw primaryHardFailure
        }

        /// The primary's failure as one that goes on to a mirror; any other is thrown. A primary cancelled for the
        /// mirror counts as timed out, unless the request's body left in that moment: then the primary may be acting on
        /// it, and the request ends as a timeout.
        private func hardFailure(of error: any Error) throws -> HardFailure {
            let path = path
            if isHandingOver, error is CancellationError {
                guard !primaryHasStarted() else {
                    log.error("send [\(path, privacy: .public)] primary took the request as it was handed over — giving up")
                    throw APIError.unreachable(.timedOut)
                }
                return .error(.unreachable(.timedOut))
            }
            if let failure = error as? HardFailure { return failure }
            log.error("send [\(path, privacy: .public)] primary failed non-recoverably: \(MirroredTransport.describeFailure(error), privacy: .public)")
            throw error
        }
    }
}

// MARK: - Mirror first

extension MirroredTransport {
    /// What `sendViaMirrorThenPrimary` does next.
    enum MirrorFirstStep: Equatable {
        /// The request ends with this answer, the mirror's when `fromMirror`.
        case answer(APIResponse, fromMirror: Bool)
        /// Look a mirror up, after dropping the one that failed hard, if any.
        case lookForMirror(dropping: MirrorResolver.Resolved?)
        /// Send the request to this mirror, watched by `mirrorProgress`.
        case askMirror(MirrorResolver.Resolved)
        /// Send the request to the primary, watched by `primaryProgress`.
        case askPrimary
        /// Stop the mirror's send (`mirrorProgress.cancel()`); its end comes as its event.
        case stopMirror
        case wait
    }

    /// A request's attempts on its preferred mirror and the primary: the next step after each event, by the rules of
    /// `sendViaMirrorThenPrimary`, logged. Not `Attempts` with the roles swapped: the two differ in which failures move
    /// the request on, which side needs a lookup, how a stop ends and what the preference learns.
    struct MirrorFirstAttempts {
        /// Where the mirror side is.
        private enum Mirror {
            case lookingUp
            /// Found while the primary had the request's body: it takes the body if the primary fails before taking it.
            case found(MirrorResolver.Resolved)
            case sending(MirrorResolver.Resolved)
            /// No mirror can answer now.
            case done
        }

        let request: APIRequest
        let silence: TimeInterval
        let primaryFailure: PrimaryFailure
        /// The mirror's send, a new one for each.
        private(set) var mirrorProgress = RequestProgress()
        /// The primary's send.
        let primaryProgress = RequestProgress()
        /// No mirror was found or answered: later requests go to the primary.
        private(set) var hasFoundNoMirror = false
        private var mirror = Mirror.lookingUp
        /// One mirror failed hard and was dropped for another: the next is the last.
        private var hasDroppedAMirror = false
        /// The mirror's send was stopped for the primary.
        private var isStoppingMirror = false
        /// The request's body went to the primary, which may be acting on it.
        private var isHandedOver = false
        private var isPrimaryAsked = false
        /// Why the primary has no answer, once it failed.
        private var primaryError: (any Error)?

        var path: String { request.target.loggedPath }

        /// Whether a silent mirror can hand this request over at all.
        var canHandOver: Bool { request.canBeHandedOver && silence < request.timeoutInterval }

        init(request: APIRequest, silence: TimeInterval, primaryFailure: PrimaryFailure) {
            self.request = request
            self.silence = silence
            self.primaryFailure = primaryFailure
        }

        mutating func step(after event: Event) throws -> MirrorFirstStep {
            switch event {
            case let .mirrorReady(route):
                return try stepAfterLookup(route)
            case let .mirror(.success(response)):
                return .answer(response, fromMirror: true)
            case let .mirror(.failure(error)):
                return try stepAfterMirrorFailure(error)
            case .silent:
                return stepAfterSilence()
            case let .primary(.success(response)):
                let path = path
                log.debug("send [\(path, privacy: .public)] primary answered \(response.status)")
                return .answer(response, fromMirror: false)
            case let .primary(.failure(error)):
                return try stepAfterPrimaryFailure(error)
            }
        }

        private mutating func stepAfterLookup(_ route: MirrorResolver.Resolved?) throws -> MirrorFirstStep {
            let path = path
            guard let route else {
                mirror = .done
                hasFoundNoMirror = true
                // The primary failed before taking the body, and no mirror is left to take it.
                if let primaryError { throw primaryError }
                guard !isPrimaryAsked else {
                    log.notice("send [\(path, privacy: .public)] no mirror found — waiting for the primary")
                    return .wait
                }
                // The primary is the only route left, and its answer or failure says more than the mirror's.
                log.error("send [\(path, privacy: .public)] no mirror found — trying primary")
                isPrimaryAsked = true
                return .askPrimary
            }
            // The primary has the body: this mirror takes it only once the primary has failed before taking it.
            if isHandedOver, primaryError == nil {
                mirror = .found(route)
                return .wait
            }
            return ask(route)
        }

        private mutating func ask(_ route: MirrorResolver.Resolved) -> MirrorFirstStep {
            mirror = .sending(route)
            mirrorProgress = RequestProgress()
            return .askMirror(route)
        }

        private mutating func stepAfterSilence() -> MirrorFirstStep {
            let path = path
            let silence = silence
            guard !isPrimaryAsked else { return .wait }
            switch mirror {
            case .lookingUp:
                isPrimaryAsked = true
                if request.target.method == .get {
                    log.notice("send [\(path, privacy: .public)] no mirror after \(silence) s — asking the primary too")
                } else {
                    log.notice("send [\(path, privacy: .public)] no mirror after \(silence) s — handing the request over to the primary")
                    isHandedOver = true
                }
                return .askPrimary
            case .sending where mirrorProgress.hasStarted:
                log.debug("send [\(path, privacy: .public)] mirror started — waiting for its answer")
                return .wait
            case .sending where request.target.method == .get:
                log.notice("send [\(path, privacy: .public)] mirror silent for \(silence) s — asking the primary too")
                isPrimaryAsked = true
                return .askPrimary
            case .sending:
                log.notice("send [\(path, privacy: .public)] mirror silent for \(silence) s — stopping it for the primary")
                isStoppingMirror = true
                return .stopMirror
            case .found, .done:
                return .wait
            }
        }

        private mutating func stepAfterMirrorFailure(_ error: any Error) throws -> MirrorFirstStep {
            let path = path
            let described = MirroredTransport.describeFailure(error)
            guard case let .sending(route) = mirror else { return .wait }
            if isStoppingMirror {
                // However the stopped send ended, its body may have left in that moment: then it is never sent twice.
                isStoppingMirror = false
                mirror = .done
                guard !mirrorProgress.hasStarted else {
                    log.error("send [\(path, privacy: .public)] mirror took the request as it was stopped — giving up")
                    throw APIError.unreachable(.timedOut)
                }
                isHandedOver = true
                isPrimaryAsked = true
                return .askPrimary
            }
            if MirroredTransport.isHardFailure(error), !hasDroppedAMirror {
                log.notice("send [\(path, privacy: .public)] mirror hard-failed (\(described, privacy: .public)) — looking up another")
                hasDroppedAMirror = true
                mirror = .lookingUp
                return .lookForMirror(dropping: route)
            }
            mirror = .done
            // Both failed: the primary's failure says more than the mirror's.
            if let primaryError { throw primaryError }
            if MirroredTransport.isNoMirrorAnswer(error) {
                hasFoundNoMirror = true
                guard !isPrimaryAsked else { return .wait }
                log.error("send [\(path, privacy: .public)] no mirror answered (\(described, privacy: .public)) — trying primary")
                isPrimaryAsked = true
                return .askPrimary
            }
            guard isPrimaryAsked else { throw error }
            log.notice("send [\(path, privacy: .public)] mirror failed (\(described, privacy: .public)) — waiting for the primary")
            return .wait
        }

        private mutating func stepAfterPrimaryFailure(_ error: any Error) throws -> MirrorFirstStep {
            let path = path
            let described = MirroredTransport.describeFailure(error)
            // Kept for the deadline, should no mirror answer: it says more than a timeout.
            if let failure = error as? HardFailure {
                primaryFailure.set(failure)
            } else if let error = error as? APIError {
                primaryFailure.set(.error(error))
            }
            // A primary that took the body may be acting on it: the request ends with its failure.
            if isHandedOver, primaryProgress.hasStarted { throw error }
            switch mirror {
            case let .found(route):
                log.notice("send [\(path, privacy: .public)] primary failed (\(described, privacy: .public)) before taking the request — back to the mirror")
                primaryError = error
                return ask(route)
            case .lookingUp, .sending:
                log.notice("send [\(path, privacy: .public)] primary failed (\(described, privacy: .public)) — waiting for the mirror")
                primaryError = error
                return .wait
            case .done:
                throw error
            }
        }
    }
}

extension APIRequest {
    /// Whether the transport can see that the primary has not started on this request (`RequestProgress`), so that a
    /// silent primary may hand it over: a GET by its answer, a request with a body by the body. Any other shows
    /// nothing before its answer, and the primary may already be acting on it.
    var canBeHandedOver: Bool {
        if case .json = target.payload { return true }
        return target.method == .get
    }
}
