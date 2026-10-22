//
//  MirroredTransport.swift
//  DVPNSDK
//

import Foundation
import OSLog
import Synchronization

private let log = Logger.sdk(category: "http")

// MARK: - MirroredTransport

/// The backend's transport: the primary first, then its mirrors. A request whose primary attempt fails hard (no answer,
/// a TLS failure, 408 or 5xx) is retried on a mirror, and so is, when its timeout is longer, one whose primary stays
/// silent past the configuration's `mirrorRequestTimeout` (`sendViaPrimaryThenMirror` has the rules). Later requests go
/// to a mirror that answered until `refreshEndpoint` finds the primary again. The primary, the mirror resolution and the
/// mirror attempts share the request's timeout.
public final class MirroredTransport: APITransport, Sendable {
    private let session: URLSession
    /// Configures the throwaway session of a request whose answer depends on the network path (`/ip`).
    private let freshSessionConfiguration: @Sendable () -> URLSessionConfiguration
    private let resolver: MirrorResolver
    private let isReachable: @Sendable () async -> Bool
    /// The backend, and where the device token comes from.
    private let configuration: BackendConfiguration
    /// The clock a request's deadline runs on; a test steps it.
    private let clock: any Clock<Duration>

    /// The backend `configuration` names. The clients' live values build one from the `backendConfiguration`
    /// dependency when they are first used; build one yourself to wrap it (a UI test's stand-in) or without TCA.
    public convenience init(configuration: BackendConfiguration) {
        let bootstrap = MirrorsBootstrapService(
            urls: configuration.bootstrapMirrorURLs,
            timeout: configuration.mirrorRequestTimeout
        )
        let sniTransport = SNISpoofTransport(timeout: configuration.mirrorRequestTimeout)
        let resolver = MirrorResolver(
            bootstrap: bootstrap,
            sniTransport: sniTransport,
            rootCAPublicKeys: configuration.rootCAPublicKeys,
            healthTimeout: configuration.mirrorRequestTimeout
        )
        let reachability = NetworkReachability()
        self.init(
            configuration: configuration,
            sessionConfiguration: Self.makeConfiguration(),
            resolver: resolver,
            isReachable: { await reachability.isReachable }
        )
    }

    /// The seams the tests replace: the backend, the sessions' configurations, the mirrors and the reachability.
    init(
        configuration: BackendConfiguration,
        sessionConfiguration: URLSessionConfiguration,
        freshSessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { makeConfiguration(ephemeral: true) },
        resolver: MirrorResolver,
        isReachable: @escaping @Sendable () async -> Bool,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.configuration = configuration
        self.clock = clock
        session = URLSession(configuration: sessionConfiguration)
        self.freshSessionConfiguration = freshSessionConfiguration
        self.resolver = resolver
        self.isReachable = isReachable
    }

    /// Logs one line per request: the method, the path without IDs (`loggedPath`), the answer or the failure, and the
    /// time it took.
    public func send(_ request: APIRequest, headers: [String: String]) async throws -> APIResponse {
        let started = ContinuousClock.now
        let target = "\(request.target.method.rawValue) \(request.target.loggedPath)"
        do {
            let response = try await deliver(request, headers: headers)
            let answer = response.isSuccess ? "\(response.status)" : Self.describe(.answer(status: response.status, body: response.body))
            log.notice("\(target, privacy: .public): \(answer, privacy: .public) in \(Self.elapsed(since: started), privacy: .public)")
            return response
        } catch {
            log.notice("\(target, privacy: .public): \(Self.describeFailure(error), privacy: .public) after \(Self.elapsed(since: started), privacy: .public)")
            throw error
        }
    }

    private func deliver(_ request: APIRequest, headers: [String: String]) async throws -> APIResponse {
        do {
            return try await withinDeadline(of: request) { primaryFailure in
                try await self.route(request, headers: headers, primaryFailure: primaryFailure)
            }
        } catch let failure as HardFailure {
            // No other endpoint did better: the hard failure's answer, or its error, is the request's.
            switch failure {
            case let .answer(response):
                return response
            case let .error(error):
                throw error
            }
        }
    }

    public func refreshEndpoint() async {
        log.debug("refreshEndpoint start")

        guard await isReachable() else {
            log.debug("refreshEndpoint unreachable")
            return
        }

        let isPrimaryUp = await pingPrimary()
        // A ping cut short by a cancelled caller says nothing about the primary.
        guard !Task.isCancelled else {
            log.debug("refreshEndpoint cancelled")
            return
        }
        if isPrimaryUp {
            log.debug("refreshEndpoint primary OK — preferring primary")
            await resolver.primaryIsHealthy()
        } else {
            log.debug("refreshEndpoint primary down — resolving a mirror")
            await resolver.primaryIsDown()
        }
    }
}

// MARK: - Routing

private extension MirroredTransport {
    func route(_ request: APIRequest, headers: [String: String], primaryFailure: PrimaryFailure) async throws -> APIResponse {
        let path = request.target.loggedPath
        log.debug("send [\(path, privacy: .public)] start")

        // Fail fast when the device has no network at all.
        guard await isReachable() else {
            log.debug("send [\(path, privacy: .public)] unreachable — fail fast as offline")
            throw APIError.offline
        }

        if await resolver.shouldPreferMirror() {
            log.debug("send [\(path, privacy: .public)] preferMirror=true — going straight to mirror")
            do {
                return try await sendViaMirror(request, headers: headers, retryOnFailure: true)
            } catch let error where Self.isNoMirrorAnswer(error) {
                // The primary is the only route left, and its answer or failure says more than the mirror's.
                log.error("send [\(path, privacy: .public)] no mirror answered (\(Self.describeFailure(error), privacy: .public)) — trying primary")
                await resolver.noMirrorAnswered()
                return try await sendViaPrimary(request, headers: headers)
            }
        }

        log.debug("send [\(path, privacy: .public)] trying primary")
        return try await sendViaPrimaryThenMirror(request, headers: headers, primaryFailure: primaryFailure)
    }
}

// MARK: - Primary, then mirror

private extension MirroredTransport {
    /// Sends `request` to the primary, then to a mirror when the primary fails hard or stays silent. A primary that has
    /// not started on the request (`RequestProgress`) within `mirrorRequestTimeout`, the time its health check gets,
    /// goes on while a mirror is looked up. Once one is ready, a GET, which is safe to repeat, goes to the mirror too and
    /// the first answer wins; a request with a body is cancelled on the primary first, and ends as a timeout if its body
    /// left in that moment, so it is never sent twice. The primary keeps the whole limit when it has started (it may be
    /// answering slowly, or acting on the request), when no mirror is ready, when the request shows nothing before its
    /// answer (`canBeHandedOver`), and when the limit is no longer than that time. When the mirror's success is the
    /// request's answer, later requests go straight to the mirror until `refreshEndpoint` finds the primary again.
    func sendViaPrimaryThenMirror(_ request: APIRequest, headers: [String: String], primaryFailure: PrimaryFailure) async throws -> APIResponse {
        let progress = RequestProgress()
        var attempts = Attempts(
            request: request,
            silence: configuration.mirrorRequestTimeout,
            primaryFailure: primaryFailure,
            primaryHasStarted: { progress.hasStarted }
        )
        let silenceEnds = clock.sleep(endingIn: .seconds(attempts.silence))
        let resolver = resolver
        return try await withThrowingTaskGroup(of: Event.self) { group in
            group.addTask { await self.primaryEvent(request, headers: headers, progress: progress) }
            if attempts.canHandOver {
                group.addTask {
                    // Cut short only when the request is cancelled, which the loop then ends.
                    try? await silenceEnds()
                    return .silent
                }
            }
            defer { group.cancelAll() }
            while let event = try await group.next() {
                // A cancelled request asks no mirror: it ends now, whatever its attempts were doing.
                try Task.checkCancellation()
                switch try attempts.step(after: event) {
                case let .answer(response, fromMirror):
                    if fromMirror, response.isSuccess { await resolver.mirrorAnswered() }
                    return response
                case .lookForMirror:
                    group.addTask { await .mirrorReady((try? resolver.currentMirror()) != nil) }
                case .askMirror:
                    group.addTask { await self.mirrorEvent(request, headers: headers) }
                case .cancelPrimary:
                    progress.cancel()
                case .wait:
                    break
                }
            }
            // Not reached: the primary's attempt, and a mirror's after its failure, end the loop.
            throw primaryFailure.value ?? HardFailure.error(.unreachable(.timedOut))
        }
    }

    /// The primary's answer to `request`, or why there is none.
    func primaryEvent(_ request: APIRequest, headers: [String: String], progress: RequestProgress) async -> Event {
        do {
            return try await .primary(.success(sendViaPrimary(request, headers: headers, progress: progress)))
        } catch {
            return .primary(.failure(error))
        }
    }

    /// A mirror's answer to `request`, or why there is none.
    func mirrorEvent(_ request: APIRequest, headers: [String: String]) async -> Event {
        do {
            return try await .mirror(.success(sendViaMirror(request, headers: headers, retryOnFailure: true)))
        } catch {
            return .mirror(.failure(error))
        }
    }
}

// MARK: - Deadline

private extension MirroredTransport {
    /// Runs `operation`, a request's whole route, within the request's timeout. A `URLRequest`'s timeout only bounds the
    /// wait for the next bytes, and each mirror attempt had it in full, so a failing primary and a silent mirror added
    /// up to minutes. At the deadline the route is cancelled, and the request ends with the primary's failure when it
    /// had one (it says more than the mirror's silence), otherwise with a timeout. The primary's own timeout is as long,
    /// so the deadline would cancel a silent primary before its timeout could send the request on: the route hands such
    /// a primary over to a mirror itself, earlier, where the request allows it (`sendViaPrimaryThenMirror`).
    func withinDeadline(
        of request: APIRequest,
        _ operation: @escaping @Sendable (PrimaryFailure) async throws -> APIResponse
    ) async throws -> APIResponse {
        let primaryFailure = PrimaryFailure()
        let limit = request.timeoutInterval
        let path = request.target.loggedPath
        let deadline = clock.sleep(endingIn: .seconds(limit))
        return try await withThrowingTaskGroup(of: APIResponse?.self) { group in
            group.addTask { try await operation(primaryFailure) }
            group.addTask {
                try await deadline()
                return nil
            }
            defer { group.cancelAll() }
            if let response = try await group.next() ?? nil { return response }
            log.error("send [\(path, privacy: .public)] no answer within \(limit) s — giving up")
            throw primaryFailure.value ?? HardFailure.error(.unreachable(.timedOut))
        }
    }
}

private extension Clock<Duration> {
    /// A sleep that ends `duration` from now, however late it starts: a request's deadline, and its primary's time to
    /// start on it, count from the request's start, not from when their tasks first run.
    func sleep(endingIn duration: Duration) -> @Sendable () async throws -> Void {
        let end = now.advanced(by: duration)
        return { try await sleep(until: end, tolerance: nil) }
    }
}

/// The primary's hard failure, kept for the deadline: the request ends with it if no mirror answers in time.
final class PrimaryFailure: Sendable {
    private let failure = Mutex<HardFailure?>(nil)

    var value: HardFailure? {
        failure.withLock { $0 }
    }

    func set(_ value: HardFailure) {
        failure.withLock { $0 = value }
    }
}

// MARK: - Primary path

private extension MirroredTransport {
    func sendViaPrimary(_ request: APIRequest, headers: [String: String], progress: RequestProgress? = nil) async throws -> APIResponse {
        var urlRequest = try request.urlRequest(baseURL: configuration.backendURL)
        let sentToken = authorize(&urlRequest, with: headers)
        return try await exchange(urlRequest, sentToken: sentToken, freshConnection: request.requiresFreshConnection, progress: progress)
    }

    func pingPrimary() async -> Bool {
        let healthURL = configuration.backendURL.appendingPathComponent("health")
        let ok = await HealthCheck.succeeds(url: healthURL, timeout: configuration.mirrorRequestTimeout)
        log.debug("pingPrimary [\(healthURL.absoluteString, privacy: .public)] -> \(ok ? "OK" : "FAIL", privacy: .public)")
        return ok
    }
}

// MARK: - Mirror path

private extension MirroredTransport {
    func sendViaMirror(_ request: APIRequest, headers: [String: String], retryOnFailure: Bool) async throws -> APIResponse {
        let path = request.target.loggedPath
        let resolved = try await resolver.currentMirror()
        log.info("sendViaMirror [\(path, privacy: .public)] mirror used")
        do {
            switch resolved {
            case let .regular(host):
                let response = try await sendRegular(request, host: host, headers: headers)
                log.info("sendViaMirror [\(path, privacy: .public)] mirror answered \(response.status)")
                return response
            case let .sniSpoof(ip, sni):
                let response = try await sendSpoofed(request, ip: ip, sni: sni, headers: headers)
                log.info("sendViaMirror [\(path, privacy: .public)] mirror answered \(response.status)")
                return response
            }
        } catch {
            if retryOnFailure, Self.isHardFailure(error) {
                log.notice("sendViaMirror [\(path, privacy: .public)] mirror hard-failed (\(Self.describeFailure(error), privacy: .public)) — invalidating and re-resolving")
                await resolver.invalidate(resolved)
                return try await sendViaMirror(request, headers: headers, retryOnFailure: false)
            }
            log.error("sendViaMirror [\(path, privacy: .public)] failing: \(Self.describeFailure(error), privacy: .public)")
            throw error
        }
    }

    func sendRegular(_ request: APIRequest, host: String, headers: [String: String]) async throws -> APIResponse {
        var urlRequest = try Self.urlRequest(for: request, on: configuration.backendURL, host: host)
        let sentToken = authorize(&urlRequest, with: headers)
        return try await exchange(urlRequest, sentToken: sentToken, freshConnection: request.requiresFreshConnection)
    }

    /// Sent as if DNS had resolved `sni` to `ip`: the SNI name is the URL's host, so it is both the ClientHello's name
    /// and the `Host` header, as in the route's health probe.
    func sendSpoofed(_ request: APIRequest, ip: String, sni: String, headers: [String: String]) async throws -> APIResponse {
        var urlRequest = try Self.urlRequest(for: request, on: configuration.backendURL, host: sni)
        let sentToken = authorize(&urlRequest, with: headers)

        let transport = SNISpoofTransport(timeout: request.timeoutInterval)
        let (data, response) = try await transport.send(urlRequest, ip: ip, sni: sni, rootCAPublicKeys: configuration.rootCAPublicKeys)
        let answer = APIResponse(status: response.statusCode, body: data, sentToken: sentToken)
        // A 408 or 5xx from this mirror is worth one more mirror, as from a regular one.
        if Self.isHardFailureStatus(response.statusCode) { throw HardFailure.answer(answer) }
        return answer
    }
}

// MARK: - URLSession exchange

private extension MirroredTransport {
    /// The caller's extra headers, then the device token, which they cannot override. Returns the token sent.
    func authorize(_ request: inout URLRequest, with headers: [String: String]) -> String? {
        Self.applyHeaders(headers, to: &request)
        let token = configuration.deviceTokenProvider?.deviceToken?.token
        if let token {
            request.setValue(token, forHTTPHeaderField: "x-device-token")
        }
        return token
    }

    /// Sends `urlRequest` over the shared session, or over a throwaway one (its own connection pool, no cache) when the
    /// answer depends on the current network path; the throwaway session is invalidated once the answer is in.
    func exchange(_ urlRequest: URLRequest, sentToken: String?, freshConnection: Bool, progress: RequestProgress? = nil) async throws -> APIResponse {
        let session = freshConnection ? URLSession(configuration: freshSessionConfiguration()) : session
        defer { if freshConnection { session.finishTasksAndInvalidate() } }
        return try await Self.load(urlRequest, sentToken: sentToken, on: session, progress: progress)
    }
}

extension MirroredTransport {
    /// The answer, whatever its status, or why there is none: `CancellationError` for a cancelled caller (not a
    /// failure of the backend, so no fallback) and for a silent primary cancelled for a mirror (`progress.cancel()`,
    /// which `sendViaPrimaryThenMirror` follows up), otherwise `APIError.unreachable`. An answer or a failure another
    /// endpoint may not share (no answer, a TLS failure, 408 or 5xx) comes wrapped in `HardFailure`. `progress` watches
    /// the request.
    static func load(
        _ urlRequest: URLRequest,
        sentToken: String?,
        on session: URLSession,
        progress: RequestProgress? = nil
    ) async throws -> APIResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest, delegate: progress)
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            let unreachable = APIError.unreachable(error.code)
            throw isHardFailure(error) ? HardFailure.error(unreachable) : unreachable
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw APIError.unreachable(.unknown)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(status: 0)
        }
        let answer = APIResponse(status: httpResponse.statusCode, body: data, sentToken: sentToken)
        if isHardFailureStatus(httpResponse.statusCode) { throw HardFailure.answer(answer) }
        return answer
    }

    /// The shared session's configuration, or, `ephemeral`, a throwaway session's: no cache either way.
    static func makeConfiguration(ephemeral: Bool = false) -> URLSessionConfiguration {
        let configuration = ephemeral ? URLSessionConfiguration.ephemeral : URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }
}

// MARK: - Helpers

extension MirroredTransport {
    /// Applies every entry of `headers` to `request` via `setValue(_:forHTTPHeaderField:)`,
    /// overwriting any prior value for the same field.
    static func applyHeaders(_ headers: [String: String], to request: inout URLRequest) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    /// A failure for the log: the status or the connection failure, and the backend's error code, which the apps do
    /// not show. Never the backend's `reason`.
    /// "850 ms" below ten seconds, "12.3 s" above.
    static func elapsed(since start: ContinuousClock.Instant) -> String {
        let duration = ContinuousClock.now - start
        let milliseconds = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
        guard milliseconds >= 10000 else { return "\(milliseconds) ms" }
        return "\(Double(milliseconds / 100) / 10) s"
    }

    /// A failure as a log line names it, never printed whole: an error's user info or values can hold a file's path or
    /// a request's data. The API's errors by their answer; a mirror's or a transport's error by its case, with the
    /// domain and code of the error it wraps; anything else by its domain and code.
    static func describeFailure(_ error: any Error) -> String {
        switch error {
        case let failure as HardFailure:
            switch failure {
            case let .answer(response):
                return describe(APIError.answer(status: response.status, body: response.body))
            case let .error(error):
                return describe(error)
            }
        case let error as APIError:
            return describe(error)
        case is CancellationError:
            return "cancelled"
        case let error as MirrorError:
            return caseName(of: error)
        case let error as SNISpoofTransport.TransportError:
            switch error {
            case let .connectionFailed(wrapped), let .sendFailed(wrapped), let .receiveFailed(wrapped):
                return "\(caseName(of: error)) \(domainAndCode(of: wrapped))"
            case .invalidRootCA, .invalidStatusLine, .malformedResponse, .missingURL:
                return caseName(of: error)
            }
        default:
            return domainAndCode(of: error)
        }
    }

    /// An enum's case, without its values.
    private static func caseName(of error: any Error) -> String {
        // `Swift.`: this module has a `Mirror` of its own, the backend's.
        Swift.Mirror(reflecting: error).children.first?.label ?? String(describing: error)
    }

    private static func domainAndCode(of error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    static func describe(_ error: APIError) -> String {
        switch error {
        case .offline:
            return "offline"
        case let .unreachable(code):
            return "unreachable \(code.rawValue)"
        case let .backend(status, code):
            return "\(status) \(code ?? "-")"
        case let .invalidResponse(status):
            return "\(status) invalid response"
        }
    }

    /// `request` sent to `host` instead of `apiURL`'s host: the API's scheme, port and path, and the request's path
    /// and query, stay.
    static func urlRequest(for request: APIRequest, on apiURL: URL, host: String) throws -> URLRequest {
        try request.urlRequest(baseURL: replaceHost(in: apiURL, with: host))
    }

    static func replaceHost(in url: URL, with host: String) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MirrorError.invalidEndpoint
        }
        components.host = host
        guard let result = components.url else { throw MirrorError.invalidEndpoint }
        return result
    }

    /// The mirror path ended without an answer from any backend: no mirror to try (`MirrorError`), or a spoofed one
    /// that could not be reached. Such an error never reaches the apps, which have no words for it: the primary's
    /// answer or failure stands in for it.
    static func isNoMirrorAnswer(_ error: Error) -> Bool {
        error is MirrorError || error is SNISpoofTransport.TransportError
    }

    static func isHardFailure(_ error: Error) -> Bool {
        switch error {
        case is HardFailure:
            return true
        case let transportError as SNISpoofTransport.TransportError:
            return transportError.isHardFailure
        case let urlError as URLError:
            return isHardFailure(urlError)
        case let APIError.unreachable(code):
            return isHardFailure(URLError(code))
        case let APIError.backend(status, _):
            return isHardFailureStatus(status)
        default:
            return false
        }
    }

    private static func isHardFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .cannotLoadFromNetwork,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    /// HTTP status codes that should trigger a mirror fallback. 5xx = primary
    /// is broken; 408 = primary accepted the connection but couldn't answer
    /// in time, which a mirror may.
    static func isHardFailureStatus(_ code: Int) -> Bool {
        code == 408 || code >= 500
    }
}

private extension SNISpoofTransport.TransportError {
    /// A spoofed mirror that could not be reached or answered garbage; another mirror may work. A missing
    /// root CA or URL would fail the same way everywhere.
    var isHardFailure: Bool {
        switch self {
        case .connectionFailed, .sendFailed, .receiveFailed, .invalidStatusLine, .malformedResponse:
            true
        case .invalidRootCA, .missingURL:
            false
        }
    }
}

// MARK: - HardFailure

/// What a primary or mirror attempt ended with that another endpoint may not share: an answer (408 or 5xx) or no answer
/// at all. Internal to the transport: `send` returns the answer or throws the error.
enum HardFailure: Error {
    case answer(APIResponse)
    case error(APIError)
}
