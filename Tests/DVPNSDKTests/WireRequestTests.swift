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

    /// Every credentials request sends the node types given, comma-joined, and none for an empty list: quick, country
    /// and city credentials in the `filter` query, as the lists do, with an empty JSON body, which the backend needs; a
    /// server's in its body.
    @Test
    func credentialsSendTheNodeTypesGivenOrNone() async throws {
        let sent = try await requests { client in
            let connection = ConnectionAPIClient.live(httpClient: client)
            _ = try? await connection.quickCredentials([])
            _ = try? await connection.quickCredentials([.amneziawg])
            _ = try? await connection.quickCredentials([.wireguard, .xray])
            _ = try? await connection.countryCredentials(Self.country, [])
            _ = try? await connection.countryCredentials(Self.country, [.v2ray, .hysteria])
            _ = try? await connection.cityCredentials(Self.city, [])
            _ = try? await connection.cityCredentials(Self.city, [.v2ray])
            _ = try? await connection.serverCredentials(Self.server, NodeType.allCases)
            _ = try? await connection.serverCredentials(Self.server, [.xray])
        }

        #expect(sent.map(line) == [
            "POST https://backend.test/credentials",
            "POST https://backend.test/credentials?filter=AMNEZIAWG",
            "POST https://backend.test/credentials?filter=WIREGUARD,XRAY",
            "POST https://backend.test/country/de/credentials",
            "POST https://backend.test/country/de/credentials?filter=V2RAY,HYSTERIA2",
            "POST https://backend.test/city/berlin/credentials",
            "POST https://backend.test/city/berlin/credentials?filter=V2RAY",
            "POST https://backend.test/server/srv-1/credentials",
            "POST https://backend.test/server/srv-1/credentials",
        ])
        #expect(try sent.map(body) == [[:], [:], [:], [:], [:], [:], [:], ["protocol": Self.allNodeTypes], ["protocol": "XRAY"]])
        #expect(sent.allSatisfy { $0.timeoutInterval == 60 && $0.value(forHTTPHeaderField: "Content-Type") == "application/json" })
    }

    /// Every credentials request has a body, so a primary that stays silent can hand it to a mirror.
    @Test
    func credentialsCanBeHandedOver() async {
        let client = RecordingClient()
        let connection = ConnectionAPIClient.live(httpClient: client)
        _ = try? await connection.quickCredentials([.xray])
        _ = try? await connection.countryCredentials(Self.country, [])
        _ = try? await connection.cityCredentials(Self.city, NodeType.allCases)
        _ = try? await connection.serverCredentials(Self.server, [.xray])
        let requests = client.requests.withLock { $0 }
        #expect(requests.count == 4 && requests.allSatisfy(\.canBeHandedOver))
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

    /// The log names a request by its path without IDs: an app's account requests carry the device's.
    @Test
    func theLogShowsPathsWithoutIDs() {
        struct Target: APITarget {
            let path: String
            var method: HTTPMethod { .get }
            var payload: RequestPayload { .none }
        }
        #expect(Target(path: "/device/6f1c0e1a-9b2d-4c3e-8f7a-1b2c3d4e5f60/user").loggedPath == "/device/…/user")
        #expect(Target(path: "/country/de/city").loggedPath == "/country/de/city")
        #expect(Target(path: "/city/48213/server").loggedPath == "/city/…/server")
        // A short code stays only when it is letters: a short number could be an ID.
        #expect(Target(path: "/server/42/credentials").loggedPath == "/server/…/credentials")
        #expect(Target(path: "/city/7/server").loggedPath == "/city/…/server")
        #expect(Target(path: "/country/DE/city").loggedPath == "/country/DE/city")
        #expect(Target(path: "/ip").loggedPath == "/ip")
        #expect(Target(path: "").loggedPath.isEmpty)
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
