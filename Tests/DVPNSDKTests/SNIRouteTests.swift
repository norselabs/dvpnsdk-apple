//
//  SNIRouteTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Testing

/// A request on the SNI route is sent as if DNS had resolved the SNI name to the mirror's IP: the name is the URL's
/// host, so it is the `Host` header as well as the ClientHello's name, like the route's health probe.
struct SNIRouteTests {
    private struct Target: APITarget {
        var method: HTTPMethod { .get }
        var path: String { "/country" }
        var payload: RequestPayload { .query([URLQueryItem(name: "filter", value: "XRAY")]) }
    }

    @Test
    func theSNINameIsTheHost() throws {
        let api = try #require(URL(string: "https://api.example.test"))

        let urlRequest = try MirroredTransport.urlRequest(for: APIRequest(target: Target()), on: api, host: "cover.test")
        let url = try #require(urlRequest.url)
        let packet = String(decoding: SNISpoofTransport(timeout: 1).encode(request: urlRequest, url: url, sni: "cover.test"), as: UTF8.self)

        #expect(url.host == "cover.test")
        #expect(url.path == "/country" && url.query == "filter=XRAY")
        #expect(packet.contains("Host: cover.test\r\n"))
        #expect(!packet.contains("api.example.test"))
    }
}
