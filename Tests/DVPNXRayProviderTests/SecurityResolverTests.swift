//
//  SecurityResolverTests.swift
//  DVPNCore
//

@testable import DVPNXRayCore
@testable import DVPNXRayProvider
import Foundation
import Network
import os
import Testing

struct SecurityResolverTests {
    private let queue = DispatchQueue(label: "com.example.vpn.tests.security-resolver")

    private func node(port: Int, security: XSecurity) -> XConfigurationModel {
        XConfigurationModel(
            outbound: .vmess(VMess(address: "127.0.0.1", port: port, users: [VMess.User(id: "uid")])),
            transport: .tcp(.init()),
            security: security
        )
    }

    @Test
    func autodetectFallsBackToPlaintextWhenNoTLSServerAnswers() async throws {
        let port = try await closedLoopbackPort()
        let model = node(port: port, security: .autodetect(.init(serverName: "127.0.0.1")))

        let resolved = await XraySecurityResolver.resolve(model)

        #expect(resolved.security == .none)
        #expect(resolved.outbound == model.outbound)
        #expect(resolved.transport == model.transport)
        let proxy = try resolved.proxyOutbound()
        #expect((proxy["streamSettings"] as? [String: Any])?["security"] as? String == "none")
    }

    @Test
    func otherSecuritiesPassThroughUntouched() async {
        for security in [XSecurity.none, .tls(.init(serverName: "example.com")), .reality(.init(serverName: "x", publicKey: "k"))] {
            let model = node(port: 443, security: security)
            let resolved = await XraySecurityResolver.resolve(model)
            #expect(resolved == model)
        }
    }

    @Test
    func unresolvedAutodetectCannotBeRendered() {
        let model = node(port: 443, security: .autodetect(.init()))
        #expect(throws: XConfigurationError.unresolvedSecurity) { try model.proxyOutbound() }
    }

    /// Binds an ephemeral loopback port and releases it, so nothing listens there.
    private func closedLoopbackPort() async throws -> Int {
        let listener = try NWListener(using: .tcp, on: .any)
        let box = ListenerBox(listener)
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let port: Int = try await withCheckedThrowingContinuation { continuation in
            box.listener.newConnectionHandler = { $0.cancel() }   // NWListener refuses to start without one
            box.listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = box.listener.port?.rawValue, !resumed.withLock({ let was = $0; $0 = true; return was }) else { return }
                    continuation.resume(returning: Int(port))
                case let .failed(error):
                    guard !resumed.withLock({ let was = $0; $0 = true; return was }) else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            box.listener.start(queue: queue)
        }
        box.listener.cancel()
        try await Task.sleep(for: .milliseconds(100))
        return port
    }
}

// `@unchecked`: wraps an NWListener that is only started and cancelled from the test.
private final class ListenerBox: @unchecked Sendable {
    let listener: NWListener
    init(_ listener: NWListener) { self.listener = listener }
}
