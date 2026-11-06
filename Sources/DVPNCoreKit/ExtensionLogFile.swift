//
//  ExtensionLogFile.swift
//  DVPNSDK
//

import Foundation
import NetworkExtension
import OSLog

/// A tunnel provider's own log lines, copied to a file in the App Group so the app can add them to a log it exports:
/// iOS shows a process no other process's log, and macOS refuses its local store to a sandboxed app. One file per
/// process, replaced each time it is written.
///
/// A provider writes its file only after a failure: when its start fails, when its tunnel stops for a reason nobody
/// asked for, and when `TunnelManager` stops it after a start that timed out or never completed a handshake, telling
/// the provider first. Reading the system's store takes about ten seconds on an iPhone, and the system reports a tunnel
/// down only once its stop returns, so an ordinary disconnect or server switch writes no file.
///
/// Only what the system kept is copied, as the system kept it: an argument logged without `privacy: .public` is
/// `<private>` in the file too. Log nothing about the user, and the file carries nothing about the user.
public enum ExtensionLogFile {
    /// How far back a file reaches.
    public static let window: TimeInterval = 3600

    /// The directory the files live in, inside the App Group container; nil without one, or before the App Group is
    /// known (`DVPNCore.bootstrap(_:)` in the app, the Info.plist key in an extension).
    public static var directory: URL? {
        guard let appGroupID = TunnelEnvironment.knownAppGroupID,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            return nil
        }
#if os(tvOS)
        return container.appendingPathComponent("Library/Caches/DVPNLogs")
#else
        return container.appendingPathComponent("Library/Logs/DVPN")
#endif
    }

    /// The app's notice to a running provider that the stop it asks for next follows a failure, so that stop writes
    /// the file. The provider answers with the same bytes.
    package static let failedStopNotice = Data("DVPN.ExtensionLogFile.failedStop".utf8)

    /// Whether a stop for `reason` writes the file: one nobody asked for, such as a failure or a lost network. A stop
    /// the user, the app or the system's bookkeeping asked for (a disconnect, a server switch, a profile change, sleep)
    /// does not.
    package static func isWritten(after reason: NEProviderStopReason) -> Bool {
        switch reason {
        case .userInitiated, .providerDisabled, .configurationDisabled, .configurationRemoved, .superceded, .userLogout,
             .userSwitch, .appUpdate, .sleep, .idleTimeout:
            false
        default:
            true
        }
    }

    /// The files written so far, by name.
    public static func urls() -> [URL] {
        guard let directory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Writes this process's lines of the last `window` to `<process>.log` in `directory`.
    package static func dump(now: Date = Date(), into directory: URL? = directory) {
        guard let directory else { return }
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let subsystem = Bundle.main.bundleIdentifier ?? "DVPNCore"
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let entries = try store.getEntries(at: store.position(date: now.addingTimeInterval(-window)), matching: predicate)
            let process = ProcessInfo.processInfo.processName
            let stamp = ISO8601DateFormatter()
            stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var lines = ["# \(process) log, the hour before \(stamp.string(from: now))"]
            // One line per entry: a line break a message quotes from a node is escaped, so it cannot forge an entry.
            for case let entry as OSLogEntryLog in entries {
                let message = entry.composedMessage.escapingControlCharacters
                lines.append("\(stamp.string(from: entry.date)) \(entry.process)[\(entry.category)] \(name(of: entry.level)): \(message)")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(process).log")
            try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Log file not written: \(error.logDescription, privacy: .public)")
        }
    }

    private static func name(of level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: "undefined"
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        @unknown default: "unknown"
        }
    }
}
