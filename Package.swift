// swift-tools-version: 6.0
import Foundation
import PackageDescription

// MARK: - Binary frameworks

/// The release whose assets hold the prebuilt engines. `Frameworks/<name>.xcframework`, built by the scripts in
/// `scripts/`, takes precedence when it exists, so a change to an engine is tested without a release.
let binaryRelease = "0.6.0"
let binaryChecksums = [
    "LibXray": "bd56138e0536e8c0686733b0669cbe6aa76cf2d21f81036a49c92d27f0a599e2",
    "LibHysteria": "661d2d40702a16155518c83361558d1844ab8e60e4c9a0b91319001f5ebe36e1",
    "HevSocks5Tunnel": "369d37a2ca9d660a8e4f7eb5aad41f308b76fee1373333332aa7f6ee46279b8a",
    "WireGuardKitGo": "116f600ac33cfec571a5edaac33db86e6bd106c09d1bf1a3a3218683b5767de1",
]

func engine(_ name: String) -> Target {
    let path = "Frameworks/\(name).xcframework"
    if FileManager.default.fileExists(atPath: "\(Context.packageDirectory)/\(path)") {
        return .binaryTarget(name: name, path: path)
    }
    return .binaryTarget(
        name: name,
        url: "https://github.com/norselabs/dvpnsdk-apple/releases/download/\(binaryRelease)/\(name).xcframework.zip",
        checksum: binaryChecksums[name]!
    )
}

// MARK: - WireGuardKit's two targets

/// The files of `Sources/WireGuardKit` that make up `WireGuardKit`: the adapter, which runs the engine, and what only
/// the adapter uses. The rest of the folder is `WireGuardKitTypes`, the configuration types, which link no engine, so
/// an app can use them without one. Both targets keep upstream's folder, so its changes still apply as they are.
let wireGuardKitAdapterFiles = [
    "WireGuardAdapter.swift", "PacketTunnelSettingsGenerator.swift", "DNSResolver.swift", "Array+ConcurrentMap.swift",
    "IPAddress+AddrInfo.swift", "Exports.swift",
]
let wireGuardKitTypeFiles = ((try? FileManager.default.contentsOfDirectory(
    atPath: "\(Context.packageDirectory)/Sources/WireGuardKit"
)) ?? []).filter { !wireGuardKitAdapterFiles.contains($0) }

// MARK: - Package

let package = Package(
    name: "DVPNSDK",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
    ],
    products: [
        // The app: the backend client and the tunnels' manager.
        .library(name: "DVPNSDK", targets: ["DVPNSDK"]),
        .library(name: "DVPNTunnel", targets: ["DVPNTunnel"]),
        .library(name: "DVPNCoreKit", targets: ["DVPNCoreKit"]),
        .library(name: "DVPNSplitTunnelCore", targets: ["DVPNSplitTunnelCore"]),
        // The extensions: one provider each.
        .library(name: "DVPNWireGuardProvider", targets: ["DVPNWireGuardProvider"]),
        .library(name: "DVPNXRayProvider", targets: ["DVPNXRayProvider"]),
        .library(name: "DVPNHysteriaProvider", targets: ["DVPNHysteriaProvider"]),
        .library(name: "DVPNSplitTunnelProvider", targets: ["DVPNSplitTunnelProvider"]),
        // The protocols' models, for an extension or app of your own.
        .library(name: "DVPNXRayCore", targets: ["DVPNXRayCore"]),
        .library(name: "DVPNWireGuardCore", targets: ["DVPNWireGuardCore"]),
        .library(name: "DVPNHysteriaCore", targets: ["DVPNHysteriaCore"]),
        .library(name: "DVPNProxyProviderCore", targets: ["DVPNProxyProviderCore"]),
        .library(name: "WireGuardKit", targets: ["WireGuardKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
    ],
    targets: [
        // MARK: - App only

        .target(
            name: "DVPNSDK",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "DVPNTunnel",
            dependencies: [
                "DVPNSDK",
                "DVPNCoreKit",
                "DVPNXRayCore",
                "DVPNWireGuardCore",
                "DVPNHysteriaCore",
                "DVPNSplitTunnelCore",
                "WireGuardKitTypes",
            ]
        ),

        // MARK: - Extension-safe core

        .target(name: "DVPNCoreKit"),
        .target(name: "DVPNXRayCore", dependencies: ["DVPNCoreKit"]),
        .target(name: "DVPNWireGuardCore", dependencies: ["DVPNCoreKit", "WireGuardKitTypes"]),
        .target(name: "DVPNHysteriaCore", dependencies: ["DVPNCoreKit"]),
        .target(name: "DVPNSplitTunnelCore", dependencies: ["DVPNCoreKit"]),

        // MARK: - Packet tunnel providers

        // The utun descriptor lookup hev-socks5-tunnel needs (the kernel-control ABI in C).
        .target(name: "DVPNProxyProviderC"),
        .target(name: "DVPNProxyProviderCore", dependencies: ["DVPNCoreKit", "DVPNProxyProviderC", "HevSocks5Tunnel"]),
        .target(name: "DVPNWireGuardProvider", dependencies: ["DVPNCoreKit", "DVPNWireGuardCore", "WireGuardKit"]),
        .target(name: "DVPNXRayProvider", dependencies: ["DVPNCoreKit", "DVPNXRayCore", "DVPNProxyProviderCore", "LibXray"]),
        .target(
            name: "DVPNHysteriaProvider",
            dependencies: ["DVPNCoreKit", "DVPNHysteriaCore", "DVPNProxyProviderCore", "LibHysteria"]
        ),

        // MARK: - Split-tunnel proxy (macOS)

        // A transparent proxy, not a packet tunnel; empty on the other platforms.
        .target(name: "DVPNSplitTunnelProvider", dependencies: ["DVPNCoreKit", "DVPNSplitTunnelCore"]),

        // MARK: - WireGuardKit (WireGuard LLC's, from amneziawg-apple; MIT, see Sources/WireGuardKit/COPYING)

        .target(
            name: "WireGuardKitTypes",
            dependencies: ["WireGuardKitC"],
            path: "Sources/WireGuardKit",
            exclude: ["COPYING"] + wireGuardKitAdapterFiles,
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "WireGuardKit",
            dependencies: ["WireGuardKitTypes", "WireGuardKitC", "WireGuardKitGo"],
            exclude: wireGuardKitTypeFiles,
            sources: wireGuardKitAdapterFiles,
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        .target(name: "WireGuardKitC", publicHeadersPath: "."),

        // MARK: - Engines

        engine("LibXray"), // scripts/build-libxray.sh
        engine("LibHysteria"), // scripts/build-libhysteria.sh
        engine("HevSocks5Tunnel"), // scripts/build-hev.sh
        engine("WireGuardKitGo"), // scripts/build-wireguard-go.sh

        // MARK: - Tests

        .testTarget(name: "DVPNSDKTests", dependencies: ["DVPNSDK"]),
        .testTarget(
            name: "DVPNCoreTests",
            dependencies: ["DVPNCoreKit", "DVPNXRayCore", "DVPNWireGuardCore", "DVPNHysteriaCore", "DVPNSplitTunnelCore", "DVPNTunnel"],
            resources: [.copy("Fixtures")]
        ),
        // Links the real LibXray macOS slice so libXray's share-link conversion and config validation run under
        // `swift test`. Never calls runXray (one instance per process; testXray refuses otherwise).
        .testTarget(
            name: "DVPNXRayProviderTests",
            dependencies: ["DVPNCoreKit", "DVPNXRayCore", "DVPNXRayProvider"],
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .testTarget(name: "DVPNProxyProviderCoreTests", dependencies: ["DVPNCoreKit", "DVPNProxyProviderCore"]),
        .testTarget(name: "WireGuardKitTests", dependencies: ["WireGuardKitTypes"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Links the real WireGuardKitGo macOS slice, in a bundle of its own, so the settings WireGuardKit's adapter hands
        // the system are built under `swift test`. Never starts the engine.
        .testTarget(name: "DVPNWireGuardProviderTests", dependencies: ["DVPNCoreKit", "DVPNWireGuardProvider", "WireGuardKit"]),
    ],
    swiftLanguageModes: [.v6]
)
