//
//  ExtensionLogFileTests.swift
//  DVPNSDK
//

@testable import DVPNCoreKit
import Foundation
import NetworkExtension
import os
import Testing

/// A provider's log file holds the lines the system kept of its process, in the export's line format, with
/// private arguments redacted as the system keeps them. Only a stop nobody asked for writes it.
struct ExtensionLogFileTests {
    /// A stop someone asked for writes no file: reading the system's store would hold the stop up.
    @Test(arguments: [
        NEProviderStopReason.userInitiated, .providerDisabled, .configurationDisabled, .configurationRemoved,
        .superceded, .userLogout, .userSwitch, .appUpdate, .sleep, .idleTimeout,
    ])
    func aStopSomeoneAskedForWritesNoFile(reason: NEProviderStopReason) {
        #expect(!ExtensionLogFile.isWritten(after: reason))
    }

    /// A stop nobody asked for, such as a failure or a lost network, writes the file.
    @Test(arguments: [
        NEProviderStopReason.none, .providerFailed, .noNetworkAvailable, .unrecoverableNetworkChange,
        .authenticationCanceled, .configurationFailed, .connectionFailed,
    ])
    func aStopNobodyAskedForWritesTheFile(reason: NEProviderStopReason) {
        #expect(ExtensionLogFile.isWritten(after: reason))
    }

    @Test
    func theFileHoldsALineLoggedJustBefore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = "ExtensionLogFileTests \(UUID().uuidString)"
        let secret = "secret-\(UUID().uuidString)"
        let logger = makeLogger(category: "ExtensionLogFileTests")
        logger.notice("\(marker, privacy: .public) token \(secret, privacy: .private)")

        ExtensionLogFile.dump(into: directory)

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let file = try #require(files.first { $0.pathExtension == "log" })
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("# \(ProcessInfo.processInfo.processName) log, the hour before "))
        #expect(text.contains(marker))
        #expect(!text.contains(secret), "a private argument is not in the file")
        #expect(text.contains("<private>"))
    }

    /// A line break in a message, such as one an engine's error quotes from a node, stays on its entry's line, escaped:
    /// it cannot add a line that reads as an entry of its own.
    @Test
    func aLineBreakInAMessageStaysOnItsLine() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = "ExtensionLogFileTests \(UUID().uuidString)"
        let forged = "2026-11-06T12:00:00.000Z DVPN[Tunnel] notice: forged \(UUID().uuidString)"
        makeLogger(category: "ExtensionLogFileTests").error("\(marker, privacy: .public): abc\n\(forged, privacy: .public)")

        ExtensionLogFile.dump(into: directory)

        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(!lines.contains { $0.hasPrefix(forged) }, "no line of the file starts with the forged text")
        #expect(lines.contains { $0.contains(marker) && $0.hasSuffix(#": abc\n"# + forged) })
    }
}
