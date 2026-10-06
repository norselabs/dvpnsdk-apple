// swift-tools-version: 6.0
import Foundation
import PackageDescription

// MARK: - Binary frameworks

/// The release whose assets hold the prebuilt engines. `Frameworks/<name>.xcframework`, built by the scripts in
/// `scripts/`, takes precedence when it exists, so a change to an engine is tested without a release.
let binaryRelease = "0.1.0"
let binaryChecksums = [
    "LibXray": "4ed44ed79cd21a2f88e92c3dfadfc1cc189a03e93692255592648bb85ec7b5a2",
    "LibHysteria": "83750f6bd6356a76fa1239ab3f8286493c8b75ccea04ead15c2b36c0af81841f",
    "HevSocks5Tunnel": "35622e4517760a07549389f372f374300ee35113b2c6425010433bb8c42950df",
    "WireGuardKitGo": "b077fe5db065df3a350ff0d2b7e34fdf8d8fdeb95522e33a5d2b2066a7f3fcb5",
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

/// `swift test` links a C stub of the WireGuard engine instead (scripts/test.sh): one test binary holds every test
/// target, and a binary can hold only one Go runtime, which the Xray tests take with LibXray.
let wireGuardGo: Target = Context.environment["DVPNSDK_WIREGUARD_GO_STUB"] == nil
    ? engine("WireGuardKitGo")
    : .target(name: "WireGuardKitGo", path: "Tests/WireGuardKitGoStub")

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
                "WireGuardKit",
            ]
        ),

        // MARK: - Extension-safe core

        .target(name: "DVPNCoreKit"),
        .target(name: "DVPNXRayCore", dependencies: ["DVPNCoreKit"]),
        .target(name: "DVPNWireGuardCore", dependencies: ["DVPNCoreKit", "WireGuardKit"]),
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
            name: "WireGuardKit",
            dependencies: ["WireGuardKitC", "WireGuardKitGo"],
            exclude: ["COPYING"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        .target(name: "WireGuardKitC", publicHeadersPath: "."),

        // MARK: - Engines

        engine("LibXray"), // scripts/build-libxray.sh
        engine("LibHysteria"), // scripts/build-libhysteria.sh
        engine("HevSocks5Tunnel"), // scripts/build-hev.sh
        wireGuardGo, // scripts/build-wireguard-go.sh

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
        .testTarget(name: "WireGuardKitTests", dependencies: ["WireGuardKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ],
    swiftLanguageModes: [.v6]
)
