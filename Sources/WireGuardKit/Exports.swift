//
//  Exports.swift
//  DVPNSDK
//

// The configuration types are WireGuardKitTypes, which links no engine. WireGuardKit re-exports them, so that the
// adapter's files and `import WireGuardKit` still have every type.
@_exported import WireGuardKitTypes
