//
//  TrustTests.swift
//  DVPNSDK
//

@testable import DVPNSDK
import Foundation
import Security
import Testing

/// The SNI route trusts a mirror whose first certificate one of the configured root keys signed: the key in either DER
/// form, any RSA size, several keys at once, and nothing but the leaf.
struct TrustTests {
    private func trust(_ certificates: [Data]) throws -> SecTrust {
        let certificates = try certificates.map { try #require(SecCertificateCreateWithData(nil, $0 as CFData)) }
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust)
        return try #require(trust)
    }

    @Test
    func aLeafTheRootSignedIsTrustedWithTheKeyInEitherForm() throws {
        let presented = try trust([TrustFixtures.mirrorLeaf])
        #expect(SNISpoofTransport.isSignedByTrustedRoot(presented, rootCAPublicKeys: [TrustFixtures.testRootSPKI]))
        #expect(SNISpoofTransport.isSignedByTrustedRoot(presented, rootCAPublicKeys: [TrustFixtures.testRootPKCS1]))
    }

    @Test
    func aLeafAnotherRootSignedIsNotTrusted() throws {
        let presented = try trust([TrustFixtures.otherLeaf])
        #expect(!SNISpoofTransport.isSignedByTrustedRoot(presented, rootCAPublicKeys: [TrustFixtures.testRootSPKI]))
    }

    /// During a key rotation both keys are configured, and either one will do.
    @Test
    func anyOfSeveralKeysWillDo() throws {
        let keys = [TrustFixtures.otherRootPKCS1, TrustFixtures.testRootSPKI]
        #expect(SNISpoofTransport.isSignedByTrustedRoot(try trust([TrustFixtures.mirrorLeaf]), rootCAPublicKeys: keys))
        #expect(SNISpoofTransport.isSignedByTrustedRoot(try trust([TrustFixtures.otherLeaf]), rootCAPublicKeys: keys))
    }

    @Test
    func aRootOfAnotherSizeWorks() throws {
        #expect(SNISpoofTransport.isSignedByTrustedRoot(try trust([TrustFixtures.bigLeaf]), rootCAPublicKeys: [TrustFixtures.bigRootSPKI]))
    }

    /// A certificate behind the leaf proves nothing: only the one the server holds the key of counts.
    @Test
    func onlyTheLeafCounts() throws {
        let presented = try trust([TrustFixtures.otherLeaf, TrustFixtures.mirrorLeaf])
        #expect(!SNISpoofTransport.isSignedByTrustedRoot(presented, rootCAPublicKeys: [TrustFixtures.testRootSPKI]))
    }

    @Test
    func withoutAUsableKeyNothingIsTrusted() throws {
        let presented = try trust([TrustFixtures.mirrorLeaf])
        #expect(!SNISpoofTransport.isSignedByTrustedRoot(presented, rootCAPublicKeys: []))
        #expect(!SNISpoofTransport.isSignedByTrustedRoot(presented, rootCAPublicKeys: [Data([1, 2, 3])]))
    }
}
