#!/bin/sh
# Checks the engines in Frameworks/ before they are used or released: each has the five slices, each slice holds
# the engine it is named after, and none links code this package keeps out of them — GPL or LGPL libraries, and in
# LibXray what GoBridge/xray-core removes. The build scripts run it after a build, and scripts/check.sh and
# scripts/make-release-assets.sh before using what is there, so an engine built from the unpatched sources is caught.
#
#   scripts/check-frameworks.sh [LibXray|LibHysteria|HevSocks5Tunnel|WireGuardKitGo]...   (default: all four)
set -eu
cd "$(dirname "$0")/.."

# Every engine has these slices (scripts/make-static-frameworks.py names them).
EXPECTED_SLICES="ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64 tvos-arm64 tvos-arm64_x86_64-simulator"

# Strings no engine may contain: one module path per line, then why.
FORBIDDEN_EVERYWHERE='github.com/sagernet/|GPL-3.0 (sing, sing-shadowsocks)
github.com/juju/ratelimit|LGPL-3.0'
# Strings LibXray may not contain, removed by the patches in GoBridge/xray-core.
FORBIDDEN_IN_XRAY='xray-core/proxy/shadowsocks_2022|Shadowsocks 2022, removed by no-shadowsocks-2022.patch
github.com/pelletier/go-toml|the TOML config loader, removed by no-yaml-toml.patch
github.com/ghodss/yaml|the YAML config loader, removed by no-yaml-toml.patch'

die() {
    echo "check-frameworks: $*" >&2
    exit 1
}

# contains <file> <string>: whether the binary holds the string anywhere.
contains() {
    LC_ALL=C grep -a -F -q -- "$2" "$1"
}

# refuse <binary> <where> <list>: fails on the first string of the list the binary holds.
refuse() {
    echo "$3" | while IFS='|' read -r needle reason; do
        if contains "$1" "$needle"; then
            echo "$2 contains $needle ($reason)" >&2
            exit 1
        fi
    done || die "rebuild it with its script in scripts/"
}

# verify <engine> <string only that engine holds> <its build script>
verify() {
    engine=$1 signature=$2 script=$3
    framework=Frameworks/$engine.xcframework
    [ -f "$framework/Info.plist" ] || die "$framework is missing: run scripts/$script"

    found=$(plutil -extract AvailableLibraries raw -o - "$framework/Info.plist")
    slices=""
    i=0
    while [ "$i" -lt "$found" ]; do
        slices="$slices $(plutil -extract "AvailableLibraries.$i.LibraryIdentifier" raw -o - "$framework/Info.plist")"
        i=$((i + 1))
    done
    for slice in $EXPECTED_SLICES; do
        case " $slices " in
            *" $slice "*) ;;
            *) die "$framework has no $slice slice: run scripts/$script" ;;
        esac
    done

    for slice in $EXPECTED_SLICES; do
        binary=$(find "$framework/$slice" -name "$engine" -type f | head -n 1)
        [ -s "$binary" ] || die "$framework/$slice has no $engine binary, or an empty one"
        contains "$binary" "$signature" || die "$framework/$slice does not look like $engine (no $signature)"
        refuse "$binary" "$framework/$slice" "$FORBIDDEN_EVERYWHERE"
        [ "$engine" != LibXray ] || refuse "$binary" "$framework/$slice" "$FORBIDDEN_IN_XRAY"
    done
    echo "$framework: $(echo "$EXPECTED_SLICES" | wc -w | tr -d ' ') slices, nothing it must not link"
}

[ $# -gt 0 ] || set -- LibXray LibHysteria HevSocks5Tunnel WireGuardKitGo
for engine in "$@"; do
    case $engine in
        LibXray) verify LibXray github.com/xtls/xray-core/ build-libxray.sh ;;
        LibHysteria) verify LibHysteria github.com/apernet/hysteria/ build-libhysteria.sh ;;
        HevSocks5Tunnel) verify HevSocks5Tunnel hev_socks5_tunnel_main build-hev.sh ;;
        WireGuardKitGo) verify WireGuardKitGo github.com/amnezia-vpn/amneziawg-go/ build-wireguard-go.sh ;;
        *) echo "usage: $0 [LibXray|LibHysteria|HevSocks5Tunnel|WireGuardKitGo]..." >&2; exit 2 ;;
    esac
done
