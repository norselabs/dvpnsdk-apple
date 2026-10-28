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
| `LibXray.xcframework` | `scripts/build-libxray.sh` (`LIBXRAY_REF`) | XTLS/libXray `v26.9.9` (50b9597) → xray-core `v1.260327.1-0.20260908222543-52a412d9e2f5` (Xray-core 26.9.9) without Shadowsocks 2022 and the YAML and TOML config loaders (`GoBridge/xray-core`) and REALITY `v0.0.0-20260908062103-8cdf7bf9c7f0` without its fallback rate limiter (`GoBridge/reality`) | The latest libXray release when built. Xray-core 26.6 and later refuse `allowInsecure` in a config, which the tunnel layer follows (it pins the peer certificate instead). The parts left out are the GPL ones: Shadowsocks 2022 pulls `sing-shadowsocks`, the loaders pull GPL YAML and TOML parsers, and the rate limiter's dependency is GPL too; `scripts/check.sh` verifies the frameworks carry no GPL or LGPL code. | 2026-10-06, go1.27.1 |
| `LibHysteria.xcframework` | `scripts/build-libhysteria.sh` | `GoBridge/libhysteria` → apernet/hysteria core/v2 + extras/v2 `v2.12.2` (app/v2.12.2, 619a6f8) | The latest release when built. | 2026-09-14, go1.27.1 |
| `HevSocks5Tunnel.xcframework` | `scripts/build-hev.sh` (`HEV_TAG`) | heiher/hev-socks5-tunnel `2.19.3` (c5584fe) with its submodules hev-task-system (d0365c3), lwip (495671e), yaml (94441ec) and hev-socks5-core (dadbb54), every slice `-fno-common` | The latest release when built. From 2.12.0 hev passes on the close of a TCP connection the proxy side ends; 2.8.0, carried over from the earlier Tun2SocksKit binaries, held it until `read-write-timeout` ran out. Never below 2.15.0, the first release with the fixes for a macOS loop after a network loss (2.14.4) and for the SOCKS connect to an IPv6 address, such as the SDK's `::1`, on macOS. `-fno-common` keeps the C slices linking into one static framework. | 2026-10-28, Apple clang 21.0.0 |
| `WireGuardKitGo.xcframework` | `scripts/build-wireguard-go.sh` | `GoBridge/wireguard` (amneziawg-apple's Go bridge) → amnezia-vpn/amneziawg-go/v3 `v3.1.20260828`, on a Go runtime patched so timers count the time the device slept | The latest v3 release when built. amneziawg-go is a wire-compatible superset of wireguard-go: plain WireGuard peers work unchanged, and the AmneziaWG obfuscation parameters apply when a node sends them. The runtime patch stops handshake timers from stalling after the device sleeps. | 2026-10-06, go1.27.1 |

Toolchain: scripts pin `GOTOOLCHAIN=go1.27.1` (auto-downloaded), Xcode with iOS + tvOS SDKs.

A bump moves a pin to the latest release unless this table says why not; check the "Why this one" column still holds,
then rebuild and run `scripts/check.sh --platforms`.
