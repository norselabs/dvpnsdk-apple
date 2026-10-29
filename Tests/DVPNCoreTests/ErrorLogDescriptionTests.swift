//
//  ErrorLogDescriptionTests.swift
//  DVPNSDK
//

@testable import DVPNCoreKit
import DVPNXRayCore
import Foundation
import Network
import Testing
import WireGuardKitTypes

/// A log line or a recorded reason names an error by its words, domain and code, never whole: no file path, no Swift
/// error's values.
struct ErrorLogDescriptionTests {
    @Test
    func anSDKErrorGivesItsOwnDescription() {
        let error: any Error = XraySourceError.unreadable("the file is cut short")
        #expect(error.logDescription == XraySourceError.unreadable("the file is cut short").description)
        #expect(!error.logDescription.contains("couldn’t be completed"))
    }

    @Test
    func anSDKMessageErrorGivesItsMessageAlone() {
        let error: any Error = NSError.newError("x")
        #expect(error.logDescription == "x")
    }

    /// A Swift error that does not describe itself gives its type and case, not its `NSError` bridge's description.
    @Test
    func aPlainSwiftErrorGivesItsTypeAndCase() {
        let error: any Error = PlainError.failed
        #expect(error.logDescription == "PlainError.failed")
        #expect(!error.logDescription.contains("Error Domain="))
    }

    /// A case's values never show: a WireGuard parse error carries the key it refused.
    @Test
    func aSwiftErrorsValuesNeverShow() {
        let parse: any Error = TunnelConfiguration.ParseError.interfaceHasInvalidPrivateKey("distinct-key-value")
        #expect(parse.logDescription == "ParseError.interfaceHasInvalidPrivateKey")

        let encoding: any Error = EncodingError.invalidValue(
            "distinct-encoded-value",
            EncodingError.Context(codingPath: [], debugDescription: "distinct-debug-text")
        )
        #expect(encoding.logDescription == "EncodingError.invalidValue")
        #expect(!encoding.logDescription.contains("distinct"))
    }

    @Test
    func aSystemErrorGivesItsWordsDomainAndCode() {
        let error: any Error = NSError(domain: "Go", code: 1, userInfo: [NSLocalizedDescriptionKey: "no valid outbound found"])
        #expect(error.logDescription == "no valid outbound found (Go 1)")

        // With no words of its own, an error is named by its codes alone, once.
        let timedOut: any Error = URLError(.timedOut)
        #expect(timedOut.logDescription == "NSURLErrorDomain -1001")
    }

    /// An enum that bridges to a system domain keeps the system's words and codes, which say more than its case.
    @Test
    func aNetworkErrorKeepsItsCode() {
        let refused: any Error = NWError.posix(.ECONNREFUSED)
        #expect(refused.logDescription.contains("61"))
        #expect(refused.logDescription.contains("Network.NWError"))
    }

    /// A file error names its domain and code and the one under it, and the file and its folder (the SDK's own names),
    /// never the file's path.
    @Test
    func aFileErrorNamesNoPath() {
        let error: any Error = CocoaError(.fileWriteNoPermission, userInfo: [
            NSFilePathErrorKey: "/Users/someone/Library/Group Containers/group.example/Library/Application Support/Xray/config.json",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13),
        ])
        let text = error.logDescription
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("Group Containers"))
        #expect(!text.contains("someone"))
        #expect(text.contains("NSCocoaErrorDomain 513"))
        #expect(text.contains("NSPOSIXErrorDomain 13"))
    }
}

/// An error with no description of its own.
private enum PlainError: Error {
    case failed
}
