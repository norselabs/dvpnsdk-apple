//
//  CertificatePinTests.swift
//  DVPNCore
//

@testable import DVPNXRayCore
import Foundation
import Security
import Testing

struct CertificatePinTests {
    @Test
    func sha256HexMatchesReferenceVector() {
        #expect(
            CertificatePin.sha256Hex(der: Data("abc".utf8)) ==
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    /// The pin format is Xray's `pinnedPeerCertSha256`: hex SHA-256 over the certificate's DER, exactly what
    /// `openssl x509 -outform DER | shasum -a 256` (or `-fingerprint -sha256` without colons) prints.
    @Test
    func pinOfFixtureCertificateMatchesOpenSSL() throws {
        let der = try TestFixtures.selfSignedCertificateDER()
        let pin = CertificatePin.sha256Hex(der: der)
        #expect(pin == TestFixtures.selfSignedPin)
        #expect(pin.count == 64)
        #expect(pin == pin.lowercased())

        // Security's copy of the certificate is byte-identical to the DER we hash.
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        #expect(CertificatePin.sha256Hex(der: SecCertificateCopyData(certificate) as Data) == TestFixtures.selfSignedPin)
    }
}
