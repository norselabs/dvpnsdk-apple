//
//  TestFixtures.swift
//  DVPNCore
//

import Foundation
import Security

/// Access to `Fixtures/`. `self-signed.pem` / `self-signed.p12` (password `dvpn-test`) were generated with
/// `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj /CN=dvpn-tls-probe-test
///  -addext subjectAltName=IP:127.0.0.1,DNS:localhost` and `openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1`.
enum TestFixtures {
    enum Error: Swift.Error {
        case missingFixture(String)
        case invalidPEM
        case identityUnavailable(OSStatus)
    }

    /// `openssl x509 -in self-signed.pem -outform DER | shasum -a 256`
    static let selfSignedPin = "a81bed91f9ea24c9dfb16833f2c0407c37b110461cd2788045dc6aa145f60d6a"
    static let selfSignedP12Password = "dvpn-test"

    static func url(_ name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw Error.missingFixture("\(name).\(ext)")
        }
        return url
    }

    /// DER bytes of the certificate in `self-signed.pem`.
    static func selfSignedCertificateDER() throws -> Data {
        let pem = try String(contentsOf: url("self-signed", extension: "pem"), encoding: .utf8)
        let body = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw Error.invalidPEM }
        return der
    }

#if os(macOS)
    /// Whether `selfSignedIdentity()` works here; tests that need the identity are `.enabled(if:)` it.
    static let canImportIdentity = (try? selfSignedIdentity()) != nil

    /// The identity in `self-signed.p12`, imported into process memory only (macOS 15+).
    static func selfSignedIdentity() throws -> SecIdentity {
        let p12 = try Data(contentsOf: url("self-signed", extension: "p12"))
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: selfSignedP12Password,
            kSecImportToMemoryOnly as String: true,
        ]
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let identityValue = first[kSecImportItemIdentity as String],
              CFGetTypeID(identityValue as CFTypeRef) == SecIdentityGetTypeID()
        else {
            throw Error.identityUnavailable(status)
        }
        // Core Foundation types cannot be conditionally cast; the type ID was checked above.
        // swiftlint:disable:next force_cast
        return identityValue as! SecIdentity
    }
#endif
}
