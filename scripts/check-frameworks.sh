#!/bin/sh
# Checks the engines in Frameworks/ before they are used or released: each has the five slices, each slice holds
# the engine it is named after, and none links code this package keeps out of them — GPL or LGPL libraries, and in
# LibXray what GoBridge/xray-core removes; LibXray's timeout reader has GoBridge/xray-core's fix, and so have the
# handshake its WebSocket and HTTPUpgrade dialers make, the response they read, and the response headers and gRPC
# messages its XHTTP and gRPC dialers accept, WireGuardKitGo runs on the patched Go runtime, and
# HevSocks5Tunnel never starts hev-task-system's stack-overflow detector and has GoBridge/hev-socks5-tunnel's session
# cap fix. The build scripts run it after a build, and
# scripts/check.sh and scripts/make-release-assets.sh before using what is there, so an engine built from the
# unpatched sources is caught.
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
FORBIDDEN_IN_XRAY='github.com/pelletier/go-toml|the TOML config loader, removed by no-yaml-toml.patch
github.com/ghodss/yaml|the YAML config loader, removed by no-yaml-toml.patch
href="([/h].*?)"|the REALITY client crawling the site that answered, removed by reality-no-spider.patch'

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

# Fixes of GoBridge/xray-core that leave no string of their own, one per line: a function of xray-core, a name its
# relocations hold only with the fix, and the fix. Upstream's functions never reference those names.
XRAY_CODE_FIXES='common/buf.(*TimeoutWrapperReader).ReadMultiBufferTimeout|common/buf.ErrReadTimeout|the timeout reader returning buf.ErrReadTimeout (timeout-reader-error.patch)
transport/internet/httpupgrade.(*ConnRF).Read|httpupgrade.(*ConnRF).Read|HTTPUpgrade keeping what came with the 101 (handshake-response-limit.patch)
transport/internet/httpupgrade.dialhttpUpgrade|_context.WithTimeout|HTTPUpgrade bounding its TLS handshake (handshake-response-limit.patch)
transport/internet/splithttp.createHTTPClient|internet.MaxResponseHeader|XHTTP limiting the response headers it accepts (response-limits.patch)
transport/internet/grpc.getGrpcClient|grpc.maxHeaderList|gRPC limiting the response headers it accepts (response-limits.patch)
transport/internet/grpc.dialgRPC|grpc.maxTunMessage|gRPC limiting the messages it reads in Tun mode (response-limits.patch)'

# lacks_xray_code_fix <binary>: the first of XRAY_CODE_FIXES an architecture's Go object lacks, or nothing.
lacks_xray_code_fix() {
    archs=$(lipo -archs "$1") && [ -n "$archs" ] || { echo "any architecture"; return; }
    work=$(mktemp -d)
    for arch in $archs; do
        lipo -thin "$arch" -output "$work/lib.a" "$1" 2>/dev/null || cp "$1" "$work/lib.a"
        (cd "$work" && ar x lib.a go.o)
        missing=$(echo "$XRAY_CODE_FIXES" | while IFS='|' read -r function name fix; do
            # a relocation naming it (arm64, and data on x86_64), or a resolved call to it (x86_64); not the jump
            # back to the function's own start that every Go function has
            objdump -d -r --disassemble-symbols="_github.com/xtls/xray-core/$function" "$work/go.o" |
                awk -v n="$name" '(/RELOC/ && substr($0, length($0) - length(n) + 1) == n) ||
                    (/call/ && index($0, n ">")) { found = 1 } END { exit !found }' || { echo "$fix"; break; }
        done)
        [ -z "$missing" ] || { rm -rf "$work"; echo "$missing ($arch)"; return; }
    done
    rm -rf "$work"
}

# starts_stack_detector <binary>: whether an object of any architecture calls hev-task-system's stack-overflow
# detector. Its own object defines it either way: build-hev.sh's TPFLAGS only keep hev_task_system_init from calling it.
starts_stack_detector() {
    xcrun nm -arch all -u "$1" 2>/dev/null | grep -q '_hev_task_stack_detector_new$'
}

# has_symbol <binary> <symbol>: whether every architecture defines the global symbol; false when none is listed.
has_symbol() {
    archs=$(lipo -archs "$1") && [ -n "$archs" ] || return 1
    for arch in $archs; do
        xcrun nm -arch "$arch" -g -U "$1" 2>/dev/null | grep -q " $2\$" || return 1
    done
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
        if [ "$engine" = LibXray ]; then
            lacking=$(lacks_xray_code_fix "$binary")
            [ -z "$lacking" ] || die "$framework/$slice lacks $lacking: run scripts/$script"
        fi
        # handshake-response-limit.patch's error, which upstream has no counterpart for.
        [ "$engine" != LibXray ] || contains "$binary" 'server handshake response longer than 64 KiB' ||
            die "$framework/$slice lacks GoBridge/xray-core's handshake response limit: run scripts/$script"
        # GoBridge/wireguard's runtime patch makes Go's clock count the time the device slept.
        [ "$engine" != WireGuardKitGo ] || contains "$binary" _mach_continuous_time ||
            die "$framework/$slice runs on a Go runtime without GoBridge/wireguard's patch: run scripts/$script"
        [ "$engine" != HevSocks5Tunnel ] || ! starts_stack_detector "$binary" ||
            die "$framework/$slice starts hev-task-system's stack-overflow detector: run scripts/$script"
        # The patch carrying upstream's session cap fix (it adds hev_socks5_tunnel_evict_session) leaves
        # hev_socks5_tunnel_insert_session global; upstream's is static, so the check goes with the patch once a release
        # carries the fix.
        [ "$engine" != HevSocks5Tunnel ] ||
            ! grep -qs hev_socks5_tunnel_evict_session GoBridge/hev-socks5-tunnel/*.patch ||
            has_symbol "$binary" _hev_socks5_tunnel_insert_session ||
            die "$framework/$slice lacks GoBridge/hev-socks5-tunnel's session cap fix: run scripts/$script"
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
