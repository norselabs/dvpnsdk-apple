//
//  Logger.swift
//  DVPNCore
//

import Foundation
import os

/// All DVPN modules log under the host app's bundle identifier with a per-module category.
public func makeLogger(category: String) -> Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "DVPNCore", category: category)
}

let logger = makeLogger(category: "DVPNCoreKit")
