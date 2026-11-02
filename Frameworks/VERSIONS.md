# Engines

`Frameworks/*.xcframework` are gitignored build products; when one is here, `Package.swift` uses it instead of the
release download. Rebuild with the scripts below; each script also writes a `Frameworks/<Name>.version` stamp with the
exact inputs used and a `Frameworks/<Name>.licenses.json` licence inventory of what it links (both gitignored, and
attached to each release).

Each has `ios-arm64`, `ios-arm64_x86_64-simulator`, `macos-arm64_x86_64`, `tvos-arm64` and
`tvos-arm64_x86_64-simulator` slices as static frameworks: the Go ones are cgo c-archives (gomobile
cannot target tvOS), HevSocks5Tunnel is C.

| Framework | Script | Pinned source | Why this one | Last known build |
|---|---|---|---|---|
| `LibXray.xcframework` | `scripts/build-libxray.sh` (`LIBXRAY_REF`) | XTLS/libXray `v26.10.31` (7fe8528) → xray-core `v1.260327.1-0.20261031132019-a4a3dff5b20c` (Xray-core 26.10.31) without the YAML and TOML config loaders (`GoBridge/xray-core`) and REALITY `v0.0.0-20261014101318-83f621788ca8` without its fallback rate limiter (`GoBridge/reality`) | The latest libXray release when built; its `go.mod` asks for Go 1.27.3. Xray-core 26.6 and later refuse `allowInsecure` in a config, which the tunnel layer follows (it pins the peer certificate instead). The config loaders are left out because libXray passes JSON only, the rate limiter because its dependency, `juju/ratelimit`, is LGPL-3.0 and only a REALITY server uses it. Shadowsocks 2022 is no longer left out: since Xray-core 26.9.30 it is Xray-core's own code instead of the GPL `sing-shadowsocks`. `scripts/check.sh` verifies the frameworks carry no GPL or LGPL code. | 2026-11-02, go1.27.3 |
| `LibHysteria.xcframework` | `scripts/build-libhysteria.sh` | `GoBridge/libhysteria` → apernet/hysteria core/v2 + extras/v2 `v2.13.0` (app/v2.13.0, ca8fbd8) | The latest release when built. Its client and the SOCKS5 server `GoBridge/libhysteria` copies from it are those of 2.12.2; it moves the QUIC library, apernet/quic-go, to quic-go 0.63. | 2026-11-02, go1.27.3 |
| `HevSocks5Tunnel.xcframework` | `scripts/build-hev.sh` (`HEV_TAG`) | heiher/hev-socks5-tunnel `2.19.3` (c5584fe) with its submodules hev-task-system (d0365c3), lwip (495671e), yaml (94441ec) and hev-socks5-core (dadbb54), every slice `-fno-common`, hev-task-system without its stack-overflow detector | The latest release when built. From 2.12.0 hev passes on the close of a TCP connection the proxy side ends; 2.8.0, carried over from the earlier Tun2SocksKit binaries, held it until `read-write-timeout` ran out. Never below 2.15.0, the first release with the fixes for a macOS loop after a network loss (2.14.4) and for the SOCKS connect to an IPv6 address, such as the SDK's `::1`, on macOS. `-fno-common` keeps the C slices linking into one static framework. The stack-overflow detector is left out: it installs process-wide `SIGSEGV` and `SIGBUS` handlers in front of the Go engines' own, and its handler faults on any thread but hev's. | 2026-11-02, Apple clang 21.0.0 |
| `WireGuardKitGo.xcframework` | `scripts/build-wireguard-go.sh` | `GoBridge/wireguard` (amneziawg-apple's Go bridge) → amnezia-vpn/amneziawg-go/v3 `v3.1.20260828`, built by a copy of the pinned Go toolchain whose runtime is patched so timers count the time the device slept | The latest v3 release when built. amneziawg-go is a wire-compatible superset of wireguard-go: plain WireGuard peers work unchanged, and the AmneziaWG obfuscation parameters apply when a node sends them. The runtime patch stops handshake timers from stalling after the device sleeps; `scripts/check-frameworks.sh` checks that every slice has it. | 2026-11-02, go1.27.3 |

Toolchain: scripts pin `GOTOOLCHAIN=go1.27.3` (auto-downloaded), Xcode with iOS + tvOS SDKs.

A bump moves a pin to the latest release unless this table says why not; check the "Why this one" column still holds,
then rebuild and run `scripts/check.sh --platforms`.
