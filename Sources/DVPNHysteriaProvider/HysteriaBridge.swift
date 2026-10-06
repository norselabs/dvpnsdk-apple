//
//  HysteriaBridge.swift
//  DVPNCore
//

import DVPNCoreKit
import Foundation
import LibHysteria

/// Swift face of the libhysteria C API. Every C string returned by Go is copied and released
/// with `LibhysteriaFree` before these functions return; no raw pointers escape.
enum HysteriaBridge {
    static func start(configJSON: String) throws {
        try check(configJSON.withCString { LibhysteriaStart(UnsafeMutablePointer(mutating: $0)) }, "start")
    }

    static func stop() throws {
        try check(LibhysteriaStop(), "stop")
    }

    static var isRunning: Bool {
        LibhysteriaIsRunning() != 0
    }

    static func version() -> String {
        guard let cString = LibhysteriaVersion() else { return "unknown" }
        defer { LibhysteriaFree(cString) }
        return String(cString: cString)
    }

    /// `nil` means success; otherwise the error text owned by Go.
    private static func check(_ result: UnsafeMutablePointer<CChar>?, _ operation: String) throws {
        guard let result else { return }
        defer { LibhysteriaFree(result) }
        throw NSError.newError("Hysteria \(operation) failed: \(String(cString: result))")
    }
}
