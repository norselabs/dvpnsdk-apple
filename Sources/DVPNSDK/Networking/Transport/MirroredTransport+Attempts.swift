//
//  MirroredTransport+Attempts.swift
//  DVPNSDK
//

import Foundation
import OSLog

private let log = Logger.sdk(category: "http")

// MARK: - Attempts

extension MirroredTransport {
    /// What happened while a request was with the primary and a mirror.
    enum Event: Sendable {
        /// The primary's answer, or why there is none.
        case primary(Result<APIResponse, any Error>)
        /// The time the primary gets to start on the request is over.
        case silent
        /// The search for a mirror ended, with one ready or none.
        case mirrorReady(Bool)
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
            case let .mirrorReady(isReady):
                return try stepAfterLookup(foundMirror: isReady)
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

extension APIRequest {
    /// Whether the transport can see that the primary has not started on this request (`RequestProgress`), so that a
    /// silent primary may hand it over: a GET by its answer, a request with a body by the body. Any other shows
    /// nothing before its answer, and the primary may already be acting on it.
    var canBeHandedOver: Bool {
        if case .json = target.payload { return true }
        return target.method == .get
    }
}
