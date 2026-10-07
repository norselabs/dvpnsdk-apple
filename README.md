# DVPN SDK for Apple platforms

Everything an iOS, macOS or tvOS app needs to offer the DVPN network: the client of the DVPN SDK API (device
registration, countries, cities and servers, connection credentials, the public IP) and the tunnels that connect to
the nodes it returns, as Network Extension providers.

The tunnels are a layer of their own: an app that already talks to the DVPN SDK API with its own client can adopt
them alone ([The tunnels with your own API client](#the-tunnels-with-your-own-api-client)).

| Protocol | Engine | Notes |
|---|---|---|
| WireGuard and AmneziaWG | [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) through WireGuardKit | One engine: amneziawg-go is a superset of wireguard-go, and a configuration without AmneziaWG keys is plain WireGuard. |
| Xray and V2Ray | [Xray-core](https://github.com/XTLS/Xray-core) through [libXray](https://github.com/XTLS/libXray), with [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) | One engine for both node types: `XRAY` and `V2RAY` (the earlier node format, still deployed; TLS is detected when the tunnel starts). VMess, VLESS (REALITY, XHTTP, Vision) and Trojan. Optional TLS ClientHello fragmentation. |
| Hysteria 2 | [apernet/hysteria](https://github.com/apernet/hysteria) through `GoBridge/libhysteria`, with hev-socks5-tunnel | Salamander obfuscation, `hysteria2://` URIs. |

Requirements: iOS 18, macOS 15 or tvOS 18; Xcode 16 or later; Swift 6.

## Before you start

The SDK is free to use under the [DVPN SDK License](LICENSE.md), which asks three things of an app built on it:

1. **The DVPN SDK API only.** The SDK works with the DVPN SDK API that NORSE Labs provides, and with no other API or
   white-label VPN service.
2. **An API token.** Register with the [NORSE Labs Developer Center](https://developer.norselabs.io) to get one.
3. **Attribution.** Show your users, for example on an About or Credits screen, exactly this text:

   > Built on Sentinel. Powered by NORSE Labs.

   with visible links to <https://sentinel.co> and <https://norselabs.io>.

Anything else needs NORSE Labs' written permission. The third-party code the SDK carries keeps its own licences
([CREDITS.md](CREDITS.md)).

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/norselabs/dvpnsdk-apple", from: "0.1.0"),
]
```

The engines are prebuilt static frameworks, downloaded from this repository's releases. To build them yourself, see
[Building the engines](#building-the-engines).

## Products

A Go engine embeds the Go runtime, and a process can hold only one, so every engine runs in a packet tunnel extension
of its own, and the app links no engine at all.

| Product | Linked by | What it holds |
|---|---|---|
| `DVPNSDK` | the app | The backend client: `BackendConfiguration` and one dependency client per area (`NodeCatalogClient`, `ConnectionAPIClient`, `DeviceAPIClient`, `ConfigAPIClient`, `APIEndpointClient`, `DeviceEventsClient`); the mirrors that stand in for the API when it cannot be reached; typed `APIError`s. |
| `DVPNTunnel` | the app | `TunnelManager`: `start(from:)` connects to the node in a set of credentials, `restart()`, `stop()`, `isActive()`, `events()`. On macOS also `SplitTunnelManager`. |
| `DVPNCoreKit` | the app and every extension | `DVPNCoreConfiguration`, the App Group paths, DNS settings. |
| `DVPNWireGuardProvider`, `DVPNXRayProvider`, `DVPNHysteriaProvider` | one extension each | The `NEPacketTunnelProvider` base classes. |
| `DVPNSplitTunnelProvider` | a macOS extension | `SplitTunnelProxyProvider`, a transparent proxy that lets chosen apps bypass the VPN. |
| `DVPNSplitTunnelCore` | the macOS app | The split-tunnel setting, shared with that extension. |
| `DVPNXRayCore`, `DVPNWireGuardCore`, `DVPNHysteriaCore`, `DVPNProxyProviderCore`, `WireGuardKit` | for your own extensions | The protocols' configuration models and the plumbing the providers are built on. |

## Setup

### 1. Name the backend

The SDK has no backend of its own. Set it once at launch, before the first request:

```swift
import DVPNSDK
import Dependencies

prepareDependencies {
    $0.backendConfiguration = BackendConfiguration(
        backendURL: URL(string: "https://api.example.com")!,
        mirrorListURLs: mirrorLists,      // optional: copies of the mirror list, fetched when the API is unreachable
        rootCAPublicKeys: [rootKey],      // optional: DER, the key that signs the SNI mirrors' certificates
        deviceTokenProvider: keychain     // your DeviceTokenProvider: where the device token is kept
    )
}
```

Mirrors are optional: leave out `mirrorListURLs` and `rootCAPublicKeys` and the SDK talks to `backendURL`. When that
cannot be reached, it also asks `<backendURL>/mirrors` for a list; when no mirror answers, the request fails with the
API's own error. Without a root key, SNI mirrors are never used.

### 2. Use the clients

Each backend area has a client: a struct of async closures. Use them through
[swift-dependencies](https://github.com/pointfreeco/swift-dependencies), ready for The Composable Architecture, or
build them yourself ([without swift-dependencies](#without-swift-dependencies)).

With `@Dependency`:

```swift
@Dependency(\.deviceAPI) var deviceAPI
@Dependency(\.nodeCatalog) var nodeCatalog
@Dependency(\.connectionAPI) var connectionAPI

let nodeTypes: [NodeType] = [.wireguard, .amneziawg, .xray, .v2ray]   // the node types your extensions serve

let token = try await deviceAPI.register(.iOS, appToken)   // keep it; your DeviceTokenProvider returns it
let countries = try await nodeCatalog.countries(nodeTypes)
let credentials = try await connectionAPI.countryCredentials(countries[0], .xray)
```

#### Without swift-dependencies

The SDK does not need TCA or `@Dependency`. Skip `prepareDependencies`, build the HTTP client once and share it (it
holds the mirror state and sends the device events), and make each client you need from it:

```swift
import DVPNSDK

let configuration = BackendConfiguration(backendURL: apiURL, deviceTokenProvider: keychain)
let httpClient = DefaultHTTPClient(transport: MirroredTransport(configuration: configuration))

let deviceAPI = DeviceAPIClient.live(httpClient: httpClient)
let nodeCatalog = NodeCatalogClient.live(httpClient: httpClient)
let connectionAPI = ConnectionAPIClient.live(httpClient: httpClient)
let deviceEvents = DeviceEventsClient.live(httpClient: httpClient)

let countries = try await nodeCatalog.countries(nodeTypes)
```

#### Errors and device states

Every failure is an `APIError`: `.offline`, `.unreachable`, `.backend(status:code:)` or `.invalidResponse`, with its
`reason`, `isTransient` and `deviceState`. The SDK writes no user-facing text. Device states (unauthorized, banned,
not enrolled) also arrive as `DeviceEventsClient.events()`, from whichever request revealed them.

### 3. Add the extensions

Give the app and every extension the same App Group. Add one packet tunnel extension per protocol you ship; each
subclasses its provider and names the App Group under `DVPNAppGroupIdentifier` in its Info.plist:

```swift
import DVPNWireGuardProvider

final class PacketTunnelProvider: WireGuardPacketTunnelProvider {}
```

`XrayPacketTunnelProvider` and `HysteriaPacketTunnelProvider` work the same way.

### 4. Connect

Tell the tunnel layer which extensions the app has, then start a tunnel from a set of credentials:

```swift
import DVPNCoreKit
import DVPNTunnel

let configuration = DVPNCoreConfiguration(
    appGroupID: "group.com.example.vpn",
    protocols: [
        TunnelProtocolDescriptor(id: .wireGuard, providerBundleID: "com.example.vpn.wireguard",
                                 tunnelName: "Example VPN", readiness: .wireGuardHandshake),
        TunnelProtocolDescriptor(id: .xray, providerBundleID: "com.example.vpn.xray",
                                 tunnelName: "Example VPN", readiness: .immediate),
    ]
)
DVPNCore.bootstrap(configuration)

let tunnels = TunnelManager(settings: settings, configuration: configuration)  // settings: TunnelSettingsProviding
try await tunnels.start(from: credentials)
```

> [!IMPORTANT]
> **Ask the backend only for the node types you ship.** Credentials for a node type the app has no extension for
> fail at `start(from:)` with `TunnelsServiceError`. Pass the node types of your extensions to the catalog and
> credential calls: the Xray extension serves `.xray` and `.v2ray`, the WireGuard extension `.wireguard` and
> `.amneziawg`, the Hysteria extension `.hysteria`.

`settings` supplies the DNS servers and whether Xray fragments its TLS ClientHello.
`TunnelManager` reads both when a tunnel starts. To apply a change to either, call `restart()`: it starts the tunnel
again on the same node from the configuration the last start stored, with no new credentials. It throws
`TunnelsServiceError.noStoredConfiguration`, leaving the tunnel as it is, when nothing is stored (tvOS may purge it);
start from new credentials then.

### 5. Split tunnelling (macOS)

Add a transparent-proxy extension that subclasses `SplitTunnelProxyProvider`, name it in
`DVPNCoreConfiguration(splitTunnelProviderBundleID:)`, and apply the user's choice with `SplitTunnelManager`.

## The tunnels with your own API client

The tunnel layer is separate from the API client: `TunnelManager.start(from:)` needs nothing but a
`ConnectionCredentials` value, the SDK's model of a credentials answer. An app that already talks to the DVPN SDK API
with a client of its own can keep that client and adopt only the tunnels: it skips step 1 and the clients in step 2
(`DVPNSDK` is still compiled in, for the model), and turns each credentials answer into the model:

```swift
// body: the DVPN SDK API's answer to a credentials request, as your client received it
let credentials = try JSONDecoder().decode(DataResponse<ConnectionCredentials>.self, from: body).data
try await tunnels.start(from: credentials)
```

The model can also be filled in field by field from the same answer:

| Node type | `endpoint` | Also needs |
|---|---|---|
| WireGuard | `.wireGuard(WireGuardEndpoint(host:port:clientAddress:peerPublicKey:))` | `privateKey`: the answer's WireGuard private key (`private_key`) |
| AmneziaWG | `.amneziaWG(AmneziaWGEndpoint(wireGuard:parameters:))`, the parameters as their `[Interface]` keys (`S1`, `H1`, …) | `privateKey`, as for WireGuard |
| Xray | `.xrayNode(XrayNodeEndpoint(host:inbounds:))` | `uid`: the answer's client UUID |
| V2Ray | `.v2ray(V2RayNodeEndpoint(host:inbounds:))` | `uid`, as for Xray |
| Hysteria 2 | `.hysteria(HysteriaEndpoint(host:port:auth:sni:obfsPassword:insecure:tlsPin:))` | `uid` when the node sent no `auth` |

Which inbound of an Xray or V2Ray node to dial, TLS trust and the fallbacks are decided by `DVPNTunnel` either way,
so the result is the same as with the SDK's own client.

## How it is built

- **The SDK decodes, the tunnel decides.** `DVPNSDK` decodes a node's handshake as the node sent it; which inbound to
  dial, TLS trust and every fallback are decided in `DVPNTunnel`, next to their tests.
- **Only `DVPNTunnel` imports `DVPNSDK`.** Everything an extension runs stays free of the backend client (lint enforces
  it).
- **Mirrors.** When the API cannot be reached, requests go to mirrors: other hosts from the mirror lists, or the API
  behind a different TLS server name (SNI). An SNI mirror's certificate is trusted only when a configured root key
  signed it.
- **Backend nodes carry no certificate.** At each start the Xray extension handshakes with the node once and pins the
  certificate it presented, or uses plaintext when no TLS handshake completes.
- **No GPL code in the engines.** LibXray is built on Xray-core without Shadowsocks 2022 and without its YAML and TOML
  config loaders, and on REALITY without its fallback rate limiter (`GoBridge/`); `GoBridge/nogpl` checks the licence of
  every linked Go module, and each build writes a licence inventory for your app's acknowledgements.
- **On tvOS** the configuration files live under the App Group's `Library/Caches`, the only place the sandbox allows;
  the app writes them again at every connect.

## Building the engines

`Frameworks/<name>.xcframework`, when present, takes precedence over the release download, so a change to an engine is
tested without a release. Each script writes the framework, a `.version` stamp of its inputs and a `.licenses.json`
inventory (see [Frameworks/VERSIONS.md](Frameworks/VERSIONS.md)):

```bash
scripts/build-libxray.sh        # LibXray: libXray on the patched Xray-core and REALITY
scripts/build-libhysteria.sh    # LibHysteria: GoBridge/libhysteria
scripts/build-hev.sh            # HevSocks5Tunnel: hev-socks5-tunnel
scripts/build-wireguard-go.sh   # WireGuardKitGo: amneziawg-go, GoBridge/wireguard
```

They need Go (the pinned toolchain downloads itself), Xcode with the iOS and tvOS SDKs, and Python 3.
After a rebuild, `scripts/gen-credits.py` updates CREDITS.md from the new inventories. `scripts/make-release-assets.sh`
zips the four frameworks and prints the checksums for `Package.swift`.

## Working on it

- `scripts/bootstrap.sh` enables the pre-commit hook (SwiftFormat and SwiftLint on staged files).
- `scripts/check.sh [--fix] [--platforms]` before pushing: formatting, lint, the Go checks, the engines' licence check,
  the tests, and with `--platforms` an `xcodebuild` of every target for iOS Simulator, macOS and tvOS Simulator.
- `scripts/test.sh` runs the tests alone. They need no network or device.

## Licences

The SDK is licensed under the [DVPN SDK License](LICENSE.md) ([Before you start](#before-you-start)). The third-party
code it carries or links keeps its own licence: [CREDITS.md](CREDITS.md) lists each piece with its licence and home,
generated by `scripts/gen-credits.py` from the packages and the engines' licence inventories (`check.sh` fails when it
is stale). `Sources/WireGuardKit` and `GoBridge/wireguard` are WireGuard LLC's WireGuardKit and Go bridge as the
[AmneziaWG fork](https://github.com/amnezia-vpn/amneziawg-apple) ships them (MIT,
[COPYING](Sources/WireGuardKit/COPYING)). Xray-core and REALITY are MPL-2.0; the SDK's changes to them are the patches
in `GoBridge/`. Each release also carries every engine's `Frameworks/<name>.licenses.json`, with the full licence
texts.
