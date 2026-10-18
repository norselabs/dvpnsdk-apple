//
//  TemporaryConfigDirectory.swift
//  DVPNSDK
//

import DVPNCoreKit
import Foundation

/// Where the configuration files of this test process live: a test process cannot write the App Group container.
enum TemporaryConfigDirectory {
    static let url = FileManager.default.temporaryDirectory
        .appending(component: "dvpnsdk-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    /// Points `TunnelConfigDirectories` at `url`. Every test that writes a configuration file calls it first; the
    /// override is the same for the whole process, so calling it again changes nothing.
    static func use() {
        TunnelConfigDirectories.overrideHomeDirectory(url)
    }
}
