//
//  WireRequestTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Synchronization
import Testing

/// What every request sends: method, URL, query, body, timeout and connection, pinned so that a change to how
/// requests are built changes nothing on the wire.
struct WireRequestTests {
    /// Every node type, in the order the backend gets them for "all".
    private static let allNodeTypes = "WIREGUARD,V2RAY,XRAY,AMNEZIAWG,HYSTERIA2"

    private static let country = Country(id: "de", name: "Germany", code: "DE", serversAvailable: 1)
    private static let city = City(id: "berlin", countryID: "de", name: "Berlin", serversAvailable: 1)
    private static let server = Server(id: "srv-1", countryID: "de", cityID: "berlin", name: "s1", isAvailable: true, serverProtocol: "XRAY")

    private static let api = URL(string: "https://backend.test")!

    /// The requests `calls` makes, as `URLRequest`s on the API's URL, none of them sent.
    private func requests(_ calls: @Sendable (any HTTPClient) async -> Void) async throws -> [URLRequest] {
        let client = RecordingClient()
        await calls(client)
        return try client.requests.withLock { $0 }.map { try $0.urlRequest(baseURL: Self.api) }
    }

    private func line(_ request: URLRequest) -> String {
        "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")"
    }

    private func body(_ request: URLRequest) throws -> [String: String]? {
        guard let data = request.httpBody else { return nil }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    @Test
    func theListsAskForOneNodeTypeOrAllOfThemByLoad() async throws {
        let sent = try await requests { client in
            let catalog = NodeCatalogClient.live(httpClient: client)
            _ = try? await catalog.countries([.xray])
            _ = try? await catalog.countries(NodeType.allCases)
            _ = try? await catalog.cities("de", NodeType.allCases)
            _ = try? await catalog.cities("de", [.wireguard])
            _ = try? await catalog.servers("berlin", [.hysteria])
            _ = try? await catalog.servers("berlin", NodeType.allCases)
            _ = try? await catalog.country("de")
        }

        #expect(sent.map(line) == [
            "GET https://backend.test/country?filter=XRAY&sort=CURRENT_LOAD",
            "GET https://backend.test/country?filter=\(Self.allNodeTypes)&sort=CURRENT_LOAD",
            "GET https://backend.test/country/de/city?filter=\(Self.allNodeTypes)&sort=CURRENT_LOAD",
            "GET https://backend.test/country/de/city?filter=WIREGUARD&sort=CURRENT_LOAD",
            "GET https://backend.test/city/berlin/server?filter=HYSTERIA2&sort=CURRENT_LOAD",
            "GET https://backend.test/city/berlin/server?filter=\(Self.allNodeTypes)&sort=CURRENT_LOAD",
            "GET https://backend.test/country/de",
        ])
        #expect(sent.allSatisfy { $0.httpBody == nil && $0.timeoutInterval == 15 })
    }

    /// Quick, country and city credentials send a node type or none; a server's credentials send its list for "all",
    /// as the apps ask.
    @Test
    func credentialsSendANodeTypeOrNoneAndAServerSendsTheListForAll() async throws {
        let sent = try await requests { client in
            let connection = ConnectionAPIClient.live(httpClient: client)
            _ = try? await connection.quickCredentials(nil)
            _ = try? await connection.quickCredentials(.amneziawg)
            _ = try? await connection.countryCredentials(Self.country, nil)
            _ = try? await connection.cityCredentials(Self.city, nil)
            _ = try? await connection.cityCredentials(Self.city, .v2ray)
            _ = try? await connection.serverCredentials(Self.server, NodeType.allCases)
            _ = try? await connection.serverCredentials(Self.server, [.xray])
        }

        #expect(sent.map(line) == [
            "POST https://backend.test/credentials",
            "POST https://backend.test/credentials",
            "POST https://backend.test/country/de/credentials",
            "POST https://backend.test/city/berlin/credentials",
            "POST https://backend.test/city/berlin/credentials",
            "POST https://backend.test/server/srv-1/credentials",
            "POST https://backend.test/server/srv-1/credentials",
        ])
        #expect(try sent.map(body) == [
            [:],
            ["protocol": "AMNEZIAWG"],
            [:],
            [:],
            ["protocol": "V2RAY"],
            ["protocol": Self.allNodeTypes],
            ["protocol": "XRAY"],
        ])
        #expect(sent.allSatisfy { $0.timeoutInterval == 60 && $0.value(forHTTPHeaderField: "Content-Type") == "application/json" })
    }

    /// The IP lookup goes over a new connection, so a tunnel that just came up answers it.
    @Test
    func theIPLookupIsShortAndFresh() async throws {
        let client = RecordingClient()
        _ = try? await ConnectionAPIClient.live(httpClient: client).publicIP()
        let request = try #require(client.requests.withLock { $0.first })

        #expect(line(try request.urlRequest(baseURL: Self.api)) == "GET https://backend.test/ip")
        #expect(request.timeoutInterval == 3)
        #expect(request.requiresFreshConnection)
    }

    @Test
    func theDeviceRegistersWithItsPlatformAndTheAppToken() async throws {
        let sent = try await requests { client in
            let device = DeviceAPIClient.live(httpClient: client)
            _ = try? await device.register(.tvOS, "app-token")
            _ = try? await device.verify()
        }

        #expect(sent.map(line) == ["POST https://backend.test/device", "GET https://backend.test/device"])
        #expect(try sent.map(body) == [["platform": "TVOS", "app_token": "app-token"], nil])
        #expect(sent.allSatisfy { $0.timeoutInterval == 15 })
    }

    @Test
    func theConfigIsAskedForWithTheAppToken() async throws {
        let sent = try await requests { client in
            _ = try? await ConfigAPIClient.live(httpClient: client).minimumVersion("app-token", .iOS)
        }

        #expect(sent.map(line) == ["GET https://backend.test/config?app_token=app-token"])
        #expect(sent.allSatisfy { $0.httpBody == nil && $0.timeoutInterval == 5 })
    }
}

/// Records each request and fails it, so no request leaves the test.
private final class RecordingClient: HTTPClient {
    let requests = Mutex<[APIRequest]>([])

    func execute<T: Decodable & Sendable>(_ request: APIRequest, requestHeaders _: [String: String], as _: T.Type) async throws -> T {
        requests.withLock { $0.append(request) }
        throw URLError(.timedOut)
    }

    func refreshEndpoint() async {}

    func deviceEvents() -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.finish() }
    }
}
