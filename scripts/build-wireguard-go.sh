#!/bin/sh
# Builds Frameworks/WireGuardKitGo.xcframework, the amneziawg-go engine WireGuardKit drives, from
# GoBridge/wireguard (amneziawg-apple's Go bridge: its Makefile patches a copy of the Go runtime so timers
# count the time the device slept, then builds a cgo c-archive). amneziawg-go is a superset of
# wireguard-go: a WireGuard configuration without AmneziaWG keys behaves as plain WireGuard.
#
# Output slices: ios-arm64, ios-arm64_x86_64-simulator, macos-arm64_x86_64, tvos-arm64,
# tvos-arm64_x86_64-simulator, as static frameworks; Swift imports the result as `WireGuardKitGo`.
# GoBridge/nogpl checks the licence of every linked module before the build and writes their inventory
# (Frameworks/WireGuardKitGo.licenses.json), and scripts/check-frameworks.sh checks the binaries after it.
#
# Requirements: go (the pinned toolchain is downloaded automatically), make, Xcode with the iOS and tvOS
# SDKs. Only the WireGuard network extension may link the result (one Go runtime per process).
set -eu

cd "$(dirname "$0")/.."
ROOT="$PWD"
MODULE_DIR="$ROOT/GoBridge/wireguard"
BUILD_DIR="$ROOT/.build/wireguard-go"
OUT="$ROOT/Frameworks/WireGuardKitGo.xcframework"
LIB="libwg-go.a"

export GOTOOLCHAIN="${GO_TOOLCHAIN:-go1.27.1}"
export GOFLAGS="${GOFLAGS:--mod=mod}"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

go -C GoBridge/nogpl run . -C "$MODULE_DIR" -inventory "$ROOT/Frameworks/WireGuardKitGo.licenses.json" .

rm -rf "$BUILD_DIR/slices" "$BUILD_DIR/include"
mkdir -p "$BUILD_DIR/include"
cp "$MODULE_DIR/wireguard.h" "$BUILD_DIR/include/wireguard.h"

# build_slice SDK MIN_VERSION ARCH... — the Makefile lipos the architectures into one library.
build_slice() {
    sdk="$1"; min="$2"; shift 2
    echo "==> $sdk $*"
    make -C "$MODULE_DIR" --no-print-directory build \
        PLATFORM_NAME="$sdk" ARCHS="$*" SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)" \
        DEPLOYMENT_TARGET_CLANG_FLAG_NAME="m$sdk-version-min" DEPLOYMENT_TARGET_CLANG_ENV_NAME=MIN_VERSION \
        MIN_VERSION="$min" CONFIGURATION_BUILD_DIR="$BUILD_DIR/slices/$sdk" \
        CONFIGURATION_TEMP_DIR="$BUILD_DIR/tmp/$sdk"
}

build_slice iphoneos         18.0 arm64
build_slice iphonesimulator  18.0 arm64 x86_64
build_slice macosx           15.0 arm64 x86_64
build_slice appletvos        18.0 arm64
build_slice appletvsimulator 18.0 arm64 x86_64

rm -rf "$OUT"
args=""
for sdk in iphoneos iphonesimulator macosx appletvos appletvsimulator; do
    args="$args -library $BUILD_DIR/slices/$sdk/$LIB -headers $BUILD_DIR/include"
done
# shellcheck disable=SC2086 # word splitting is the point; a checkout path with spaces is not supported here
xcodebuild -create-xcframework $args -output "$OUT" >/dev/null

# Xcode copies library-style xcframework headers into one shared include/ dir, where several
# module.modulemap files collide; re-package the slices as static frameworks instead.
python3 scripts/make-static-frameworks.py "$OUT" "$OUT" WireGuardKitGo wireguard.h

for slice in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64 tvos-arm64 tvos-arm64_x86_64-simulator; do
    if ! grep -q "<string>$slice</string>" "$OUT/Info.plist"; then
        echo "error: $OUT is missing the $slice slice" >&2
        exit 1
    fi
done
scripts/check-frameworks.sh WireGuardKitGo

AMNEZIAWG="$(cd "$MODULE_DIR" && go list -m -f '{{.Version}}' github.com/amnezia-vpn/amneziawg-go/v3)"
{
    echo "amneziawg-go: $AMNEZIAWG"
    echo "go: $(go version), runtime patched with $(cd "$MODULE_DIR" && ls goruntime-*.diff)"
    echo "built: $(date -u +%FT%TZ)"
} > "$ROOT/Frameworks/WireGuardKitGo.version"

echo "Built $OUT"
cat "$ROOT/Frameworks/WireGuardKitGo.version"
