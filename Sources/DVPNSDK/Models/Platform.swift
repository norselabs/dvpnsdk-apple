//
//  Platform.swift
//  DVPNSDK
//

/// The device platform as the backend names it (device registration, minimum-version lookup).
public enum Platform: String, Sendable {
    case iOS = "IOS"
    case macOS = "MACOS"
    case tvOS = "TVOS"
}

extension Platform {
    /// The `/config` key that carries this platform's minimum app version.
    var versionKey: String {
        switch self {
        case .iOS:
            return "minimal_ios_version"
        case .macOS:
            return "minimal_macos_version"
        case .tvOS:
            return "minimal_tvos_version"
        }
    }
}
