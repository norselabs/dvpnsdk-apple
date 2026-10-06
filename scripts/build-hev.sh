#!/bin/bash
# Builds Frameworks/HevSocks5Tunnel.xcframework from a pinned hev-socks5-tunnel release, the C
# tun2socks the Xray and Hysteria extensions move their packets with (DVPNProxyProviderCore). It
# replaces the Tun2SocksKit package, which carried no licence.
#
#   scripts/build-hev.sh [--source <hev-socks5-tunnel checkout>]
#
# Without --source the release is cloned, with its submodules, into .build/hev-socks5-tunnel.
# Output slices: ios-arm64, ios-arm64_x86_64-simulator, macos-arm64_x86_64, tvos-arm64,
# tvos-arm64_x86_64-simulator, re-packaged as static frameworks like the Go frameworks. Needs Xcode
# (xcrun, clang, libtool, lipo, xcodebuild), make and python3; takes a few minutes.
#
# Every slice is compiled with -fno-common. Apple clang still emits lwIP's memory pools
# (`memp_memory_*_base`, up to 1 MB each) as common symbols by default, and the linker gives a
# common symbol an alignment derived from its size, up to 32 KB, which exceeds the 16 KB segment
# alignment; every consumer then logs "reducing alignment of section __DATA,__common from 0x8000
# to 0x4000" when linking. Regular zero-filled globals keep the compiler's alignment instead.
set -euo pipefail

HEV_TAG="2.8.0"
IOS_MIN="18.0"
TVOS_MIN="18.0"
MACOS_MIN="15.0"

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/.build/hev"
OUT="$ROOT/Frameworks/HevSocks5Tunnel.xcframework"
SOURCE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --source) SOURCE="$2"; shift 2 ;;
        *) echo "usage: $0 [--source <hev-socks5-tunnel checkout>]" >&2; exit 2 ;;
    esac
done

if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

if [ -z "$SOURCE" ]; then
    SOURCE="$ROOT/.build/hev-socks5-tunnel"
    if [ ! -d "$SOURCE/.git" ]; then
        echo "▶ Cloning hev-socks5-tunnel $HEV_TAG"
        git clone --quiet --branch "$HEV_TAG" --depth 1 --recurse-submodules --shallow-submodules \
            https://github.com/heiher/hev-socks5-tunnel.git "$SOURCE"
    fi
fi
actual="$(git -C "$SOURCE" describe --tags --exact-match 2>/dev/null || git -C "$SOURCE" rev-parse --short HEAD)"
if [ "$actual" != "$HEV_TAG" ]; then
    echo "error: $SOURCE is at $actual; this script builds $HEV_TAG (change HEV_TAG to move on)" >&2
    exit 1
fi

SLICES="$BUILD/slices"
HEADERS="$BUILD/include"
rm -rf "$BUILD"
mkdir -p "$SLICES" "$HEADERS"

# hev-socks5-tunnel compiles with -Wall -Werror; newer clangs add warnings the release predates
# (2.8.0: an uninitialised byte written to the wake-up pipe, -Wuninitialized-const-pointer).
# -Wno-unknown-warning-option keeps the list valid for older clangs.
CFLAGS_WARNINGS="-Wno-unknown-warning-option -Wno-uninitialized-const-pointer"

# build <slice> <sdk> <arch> <minimum-version flag>: one architecture of one slice.
build() {
    local slice=$1 sdk=$2 arch=$3 min=$4
    local clang="xcrun --sdk $sdk clang"
    echo "▶ $slice ($arch)"
    make -C "$SOURCE" --no-print-directory clean >/dev/null
    make -C "$SOURCE" --no-print-directory -j"$(sysctl -n hw.ncpu)" \
        PP="$clang" CC="$clang" AR="xcrun --sdk $sdk ar" \
        CFLAGS="-arch $arch $min -fno-common $CFLAGS_WARNINGS" \
        LFLAGS="-arch $arch $min" \
        static >/dev/null
    mkdir -p "$SLICES/$slice/archs"
    xcrun libtool -static -no_warning_for_no_symbols -o "$SLICES/$slice/archs/$arch.a" \
        "$SOURCE/bin/libhev-socks5-tunnel.a" \
        "$SOURCE/third-part/lwip/bin/liblwip.a" \
        "$SOURCE/third-part/yaml/bin/libyaml.a" \
        "$SOURCE/third-part/hev-task-system/bin/libhev-task-system.a"
}

# merge <slice>: one fat library per slice.
merge() {
    xcrun lipo -create -output "$SLICES/$1/libhev-socks5-tunnel.a" "$SLICES/$1"/archs/*.a
}

build ios       iphoneos         arm64  "-miphoneos-version-min=$IOS_MIN"
build ios-sim   iphonesimulator  arm64  "-mios-simulator-version-min=$IOS_MIN"
build ios-sim   iphonesimulator  x86_64 "-mios-simulator-version-min=$IOS_MIN"
build macos     macosx           arm64  "-mmacosx-version-min=$MACOS_MIN"
build macos     macosx           x86_64 "-mmacosx-version-min=$MACOS_MIN"
build tvos      appletvos        arm64  "-mtvos-version-min=$TVOS_MIN"
build tvos-sim  appletvsimulator arm64  "-mtvos-simulator-version-min=$TVOS_MIN"
build tvos-sim  appletvsimulator x86_64 "-mtvos-simulator-version-min=$TVOS_MIN"
for slice in ios ios-sim macos tvos tvos-sim; do merge "$slice"; done
make -C "$SOURCE" --no-print-directory clean >/dev/null

cp "$SOURCE/src/hev-main.h" "$HEADERS/"

echo "▶ Creating the xcframework"
rm -rf "$OUT" "$BUILD/HevSocks5Tunnel.xcframework"
xcodebuild -create-xcframework \
    -library "$SLICES/ios/libhev-socks5-tunnel.a"      -headers "$HEADERS" \
    -library "$SLICES/ios-sim/libhev-socks5-tunnel.a"  -headers "$HEADERS" \
    -library "$SLICES/macos/libhev-socks5-tunnel.a"    -headers "$HEADERS" \
    -library "$SLICES/tvos/libhev-socks5-tunnel.a"     -headers "$HEADERS" \
    -library "$SLICES/tvos-sim/libhev-socks5-tunnel.a" -headers "$HEADERS" \
    -output "$BUILD/HevSocks5Tunnel.xcframework" >/dev/null
# Xcode copies library-style xcframework headers into one shared include/ dir, where several
# module.modulemap files collide; re-package the slices as static frameworks instead.
python3 scripts/make-static-frameworks.py "$BUILD/HevSocks5Tunnel.xcframework" "$OUT" HevSocks5Tunnel hev-main.h

echo "▶ Checking the slices"
for lib in "$OUT"/*/HevSocks5Tunnel.framework/HevSocks5Tunnel; do
    for arch in $(xcrun lipo -archs "$lib"); do
        commons=$(xcrun nm -arch "$arch" "$lib" 2>/dev/null | awk '$2 == "C"' | wc -l | tr -d ' ')
        minos=$(xcrun otool -arch "$arch" -l "$lib" | awk '/minos/ && !seen { print $2; seen = 1 }')
        printf '  %-32s %-6s minos %-5s common symbols %s\n' "$(basename "$(dirname "$(dirname "$lib")")")" "$arch" "$minos" "$commons"
        if [ "$commons" != 0 ]; then
            echo "error: common symbols left in $lib ($arch)" >&2
            exit 1
        fi
    done
done
scripts/check-frameworks.sh HevSocks5Tunnel

# The licence inventory of what the framework links, in GoBridge/nogpl's -inventory shape, for the
# apps' licences list: hev-socks5-tunnel and the four libraries it builds in.
python3 - "$SOURCE" "$HEV_TAG" > Frameworks/HevSocks5Tunnel.licenses.json <<'PYTHON'
import json, os, re, subprocess, sys
source, tag = sys.argv[1], sys.argv[2]
modules = []
for part in [".", "third-part/hev-task-system", "third-part/lwip", "third-part/yaml", "src/core"]:
    root = os.path.join(source, part)
    git = lambda *args: subprocess.check_output(["git", "-C", root, *args], text=True).strip()
    url = re.sub(r"^https://|\.git$", "", git("remote", "get-url", "origin"))
    files = sorted(f for f in os.listdir(root) if re.match(r"(?i)^(licen[cs]e|copying|notice)", f))
    if not files:
        sys.exit(f"{part}: no licence file")
    modules.append({
        "path": url,
        "version": tag if part == "." else git("rev-parse", "--short=12", "HEAD"),
        "licenses": [{"name": f, "text": open(os.path.join(root, f), encoding="utf-8").read()} for f in files],
    })
print(json.dumps({"modules": modules}, indent=2))
PYTHON

{
    echo "hev-socks5-tunnel: $HEV_TAG ($(git -C "$SOURCE" rev-parse --short HEAD))"
    for sub in hev-task-system lwip yaml; do
        echo "  third-part/$sub: $(git -C "$SOURCE/third-part/$sub" rev-parse --short HEAD)"
    done
    echo "  src/core (hev-socks5-core): $(git -C "$SOURCE/src/core" rev-parse --short HEAD)"
    echo "clang: $(xcrun clang --version | head -1)"
    echo "built: $(date -u +%FT%TZ)"
} > Frameworks/HevSocks5Tunnel.version
echo "✓ $OUT"
cat Frameworks/HevSocks5Tunnel.version
