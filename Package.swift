// swift-tools-version: 6.0
import Foundation
import PackageDescription

// MARK: - Binary frameworks

/// The release whose assets hold the prebuilt engines. `Frameworks/<name>.xcframework`, built by the scripts in
/// `scripts/`, takes precedence when it exists, so a change to an engine is tested without a release.
let binaryRelease = "0.5.1"
let binaryChecksums = [
    "LibXray": "9fdb668ae9dfe014929fffb2d1cd31c7ba526461dcec3bd4cfaf6fc9008031b7",
    "LibHysteria": "09e310fb3f9f4db4bd771a84bc39105a43bb633aad6dab714809954ac61454d7",
    "HevSocks5Tunnel": "a3131c9f7f41e385469f28215b78e7bbb35a9c93260b866c8522beee4861c98a",
    "WireGuardKitGo": "15474497a2633000cd52937e483c2b38a0b5a0883b57d0ca0719e06ae787163d",
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
        .testTarget(name: "WireGuardKitTests", dependencies: ["WireGuardKitTypes"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ],
    swiftLanguageModes: [.v6]
)
