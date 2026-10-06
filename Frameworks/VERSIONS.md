# Engines

`Frameworks/*.xcframework` are gitignored build products; when one is here, `Package.swift` uses it instead of the
release download. Rebuild with the scripts below; each script also writes a `Frameworks/<Name>.version` stamp with the
exact inputs used and a `Frameworks/<Name>.licenses.json` licence inventory of what it links (both gitignored, and
attached to each release).

Each has `ios-arm64`, `ios-arm64_x86_64-simulator`, `macos-arm64_x86_64`, `tvos-arm64` and
`tvos-arm64_x86_64-simulator` slices as static frameworks: the Go ones are cgo c-archives (gomobile
cannot target tvOS), HevSocks5Tunnel is C.

| Framework | Script | Pinned source | Last known build |
|---|---|---|---|
| `LibXray.xcframework` | `scripts/build-libxray.sh` (`LIBXRAY_REF`) | XTLS/libXray `v26.9.9` (50b9597) → xray-core `v1.260327.1-0.20260908222543-52a412d9e2f5` (Xray-core 26.9.9) without Shadowsocks 2022 and the YAML and TOML config loaders (`GoBridge/xray-core`) and REALITY `v0.0.0-20260908062103-8cdf7bf9c7f0` without its fallback rate limiter (`GoBridge/reality`) | 2026-10-06, go1.27.1 |
| `LibHysteria.xcframework` | `scripts/build-libhysteria.sh` | `GoBridge/libhysteria` → apernet/hysteria core/v2 + extras/v2 `v2.12.2` (app/v2.12.2, 619a6f8) | 2026-09-14, go1.27.1 |
| `HevSocks5Tunnel.xcframework` | `scripts/build-hev.sh` (`HEV_TAG`) | heiher/hev-socks5-tunnel `2.8.0` (615e779) with its submodules hev-task-system, lwip, yaml and hev-socks5-core, every slice `-fno-common` | 2026-09-29, Apple clang 21.0.0 |
| `WireGuardKitGo.xcframework` | `scripts/build-wireguard-go.sh` | `GoBridge/wireguard` (amneziawg-apple's Go bridge) → amnezia-vpn/amneziawg-go/v3 `v3.1.20260828`, on a Go runtime patched so timers count the time the device slept | 2026-10-06, go1.27.1 |

Toolchain: scripts pin `GOTOOLCHAIN=go1.27.1` (auto-downloaded), Xcode with iOS + tvOS SDKs.
