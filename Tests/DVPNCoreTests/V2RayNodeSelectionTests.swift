//
//  V2RayNodeSelectionTests.swift
//  DVPNCore
//

import DVPNSDK
@testable import DVPNTunnel
@testable import DVPNXRayCore
import Foundation
import Testing

/// The rules that used to live in the SDK's decoder; V2RAY nodes stay fully supported.
struct V2RayNodeSelectionTests {
    private let uuid = "11111111-2222-3333-4444-555555555555"

    @Test
    func prefersVMessWhenBothAreOffered() throws {
        let node = V2RayNodeEndpoint(host: "203.0.113.10", inbounds: [
            V2RayInbound(port: 443, proxyProtocol: .vless, transport: .tcp),
            V2RayInbound(port: 8443, proxyProtocol: .vmess, transport: .grpc),
        ])
        let model = try V2RayNodeSelection.model(for: node, uuid: uuid)

        #expect(model.outbound == .vmess(VMess(address: "203.0.113.10", port: 8443, users: [VMess.User(id: uuid)])))
        #expect(model.transport == .grpc(.init()))
        #expect(model.security == .autodetect(StreamSettings.TLS(serverName: "203.0.113.10")), "TLS is detected at start")
    }

    @Test
    func vlessOnlyNodeIsDialledWithoutFlow() throws {
        let node = V2RayNodeEndpoint(host: "h", inbounds: [V2RayInbound(port: 443, proxyProtocol: .vless, transport: .websocket)])
        let model = try V2RayNodeSelection.model(for: node, uuid: uuid)

        #expect(model.outbound == .vless(VLESS(address: "h", port: 443, users: [VLESS.User(id: uuid)])))
        #expect(model.transport == .ws(.init()))
    }

    /// Xray-core refuses plaintext VLESS towards a public address, so such an inbound is skipped and a
    /// node offering nothing else is rejected before the extension starts.
    @Test
    func plaintextVLESSIsSkipped() throws {
        let plaintextOnly = V2RayNodeEndpoint(host: "h", inbounds: [
            V2RayInbound(port: 443, proxyProtocol: .vless, transport: .grpc, security: .plaintext),
        ])
        #expect(throws: V2RayNodeSelection.Error.plaintextVLESSOnly) { try V2RayNodeSelection.model(for: plaintextOnly, uuid: uuid) }

        let withTLS = V2RayNodeEndpoint(host: "h", inbounds: [
            V2RayInbound(port: 443, proxyProtocol: .vless, transport: .grpc, security: .plaintext),
            V2RayInbound(port: 8443, proxyProtocol: .vless, transport: .grpc, security: .tls),
        ])
        let model = try V2RayNodeSelection.model(for: withTLS, uuid: uuid)
        #expect(model.outbound == .vless(VLESS(address: "h", port: 8443, users: [VLESS.User(id: uuid)])))
    }

    @Test
    func transportsMapToTheXrayNetworks() throws {
        for (transport, network) in [(V2RayInbound.Transport.tcp, XTransport.tcp(.init())), (.grpc, .grpc(.init())), (.websocket, .ws(.init()))] {
            let node = V2RayNodeEndpoint(host: "h", inbounds: [V2RayInbound(port: 1, proxyProtocol: .vmess, transport: transport)])
            #expect(try V2RayNodeSelection.model(for: node, uuid: uuid).transport == network)
        }
    }

    @Test
    func nodeWithoutInboundsIsRejected() {
        #expect(throws: V2RayNodeSelection.Error.noUsableInbound) {
            try V2RayNodeSelection.model(for: V2RayNodeEndpoint(host: "h", inbounds: []), uuid: uuid)
        }
    }
}
