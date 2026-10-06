//
//  ResponseDecodingTests.swift
//  DVPNSDKTests
//

@testable import DVPNSDK
import Foundation
import Testing

/// The backend's wire format for the plain response models, pinned so decoder changes cannot move it.
struct ResponseDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test
    func country() throws {
        let country = try decode(Country.self, #"{"id":"de","name":"Germany","code":"DE","servers_available":3}"#)
        #expect(country == Country(id: "de", name: "Germany", code: "DE", serversAvailable: 3))
    }

    @Test
    func cityWithAndWithoutItsCountry() throws {
        let plain = try decode(City.self, #"{"id":"ber","country_id":"de","name":"Berlin","servers_available":2}"#)
        #expect(plain == City(id: "ber", countryID: "de", name: "Berlin", serversAvailable: 2))

        let json = #"""
        {"id":"ber","country_id":"de","name":"Berlin","servers_available":2,
         "country":{"id":"de","name":"Germany","code":"DE","servers_available":3}}
        """#
        let nested = try decode(City.self, json)
        #expect(nested.country == Country(id: "de", name: "Germany", code: "DE", serversAvailable: 3))
    }

    @Test
    func server() throws {
        let server = try decode(
            Server.self,
            #"{"id":"s1","country_id":"de","city_id":"ber","load":0.42,"name":"Berlin 1","is_available":true,"protocol":"XRAY"}"#
        )
        #expect(server == Server(id: "s1", countryID: "de", cityID: "ber", load: 0.42, name: "Berlin 1", isAvailable: true, serverProtocol: "XRAY"))
        #expect(server.country == nil)
    }

    @Test
    func verifyDeviceResponse() throws {
        let response = try decode(VerifyDeviceResponse.self, #"{"id":"dev-1","is_enrolled":true,"is_banned":false}"#)
        #expect(response.id == "dev-1")
        #expect(response.isEnrolled)
        #expect(!response.isBanned)
    }

    @Test
    func versionResponseInsideTheDataEnvelope() throws {
        let envelope = try decode(
            DataResponse<[VersionResponse]>.self,
            #"{"data":[{"key":"minimal_ios_version","value":"2.4.0"},{"key":"minimal_macos_version","value":"2.4.0"}]}"#
        )
        #expect(envelope.data.map(\.key) == ["minimal_ios_version", "minimal_macos_version"])
        #expect(envelope.data.first?.value == "2.4.0")
    }

    @Test
    func ipResponse() throws {
        let response = try decode(
            IPResponse.self,
            #"{"ip":"203.0.113.7","information":{"city":"Berlin","country":"Germany","country_code":"DE","latitude":52.5,"longitude":13.4}}"#
        )
        #expect(response == IPResponse(
            ip: "203.0.113.7",
            information: IPLocation(city: "Berlin", country: "Germany", countryCode: "DE", latitude: 52.5, longitude: 13.4)
        ))
    }

    @Test
    func mirrorListEntry() throws {
        let mirror = try decode(Mirror.self, #"{"type":"SNI_SPOOF","endpoint":"203.0.113.9","available_sni_options":["cdn.example"]}"#)
        #expect(mirror.type == .sniSpoof)
        #expect(mirror.endpoint == "203.0.113.9")
        #expect(mirror.availableSniOptions == ["cdn.example"])
    }

    @Test
    func storableToken() throws {
        let token = try decode(DeviceToken.self, #"{"id":"tok-1","token":"secret"}"#)
        #expect(token.id == "tok-1")
        #expect(token.token == "secret")
    }
}
