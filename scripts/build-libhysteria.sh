#!/bin/sh
# Builds Frameworks/LibHysteria.xcframework from GoBridge/libhysteria (cgo c-archive mode),
# mirroring libXray's build/app/apple_go.py so both frameworks share one recipe.
#
# Output slices: ios-arm64, ios-arm64_x86_64-simulator, macos-arm64_x86_64, tvos-arm64,
# tvos-arm64_x86_64-simulator. gomobile is not used because it cannot target tvOS.
#
# Requirements: go (the pinned toolchain is downloaded automatically), Xcode with the iOS and
# tvOS SDKs. Only the Hysteria network extension may link the result (one Go runtime per process).
# GoBridge/nogpl checks the licence of every linked module before the build and writes their inventory
# (Frameworks/LibHysteria.licenses.json, for the apps' licences list), and scripts/check-frameworks.sh
# checks the binaries after it.
set -eu

cd "$(dirname "$0")/.."
ROOT="$PWD"
MODULE_DIR="$ROOT/GoBridge/libhysteria"
BUILD_DIR="$ROOT/.build/libhysteria"
OUT="$ROOT/Frameworks/LibHysteria.xcframework"
LIB="libhysteria.a"
HEADER="libhysteria.h"

export GOTOOLCHAIN="${GO_TOOLCHAIN:-go1.27.1}"
export GOFLAGS="${GOFLAGS:--mod=mod}"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

VERSION="$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo dev)"
LDFLAGS="-s -w -buildid= -X github.com/norselabs/libhysteria.version=$VERSION"

go -C GoBridge/nogpl run . -C "$MODULE_DIR" -inventory "$ROOT/Frameworks/LibHysteria.licenses.json" ./cgo

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/include"

# build_slice GOOS GOARCH APPLE_ARCH SDK MIN_VERSION
build_slice() {
    goos="$1"; goarch="$2"; arch="$3"; sdk="$4"; min="$5"
    out="$BUILD_DIR/$sdk-$arch"
    mkdir -p "$out"
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    flags="-isysroot $sdk_path -m$sdk-version-min=$min -arch $arch"
    echo "==> $sdk $arch (GOOS=$goos GOARCH=$goarch)"
    ( cd "$MODULE_DIR" && \
      GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=1 GOFLAGS="-mod=mod -tags=$goos" \
      CC="xcrun --sdk $sdk --toolchain $sdk clang" CXX="xcrun --sdk $sdk --toolchain $sdk clang++" \
      CGO_CFLAGS="$flags" CGO_CXXFLAGS="$flags" CGO_LDFLAGS="$flags -Wl,-Bsymbolic-functions" \
      go build -trimpath -ldflags "$LDFLAGS" -buildmode=c-archive -o "$out/$LIB" ./cgo )
    cp "$out/$HEADER" "$BUILD_DIR/include/$HEADER"
}

# lipo_slices NAME SLICE_A SLICE_B
lipo_slices() {
    mkdir -p "$BUILD_DIR/$1"
    lipo -create "$BUILD_DIR/$2/$LIB" "$BUILD_DIR/$3/$LIB" -output "$BUILD_DIR/$1/$LIB"
}

build_slice ios    arm64 arm64  iphoneos          18.0
build_slice ios    arm64 arm64  iphonesimulator   18.0
build_slice ios    amd64 x86_64 iphonesimulator   18.0
build_slice darwin arm64 arm64  macosx            15.0
build_slice darwin amd64 x86_64 macosx            15.0
build_slice ios    arm64 arm64  appletvos         18.0
build_slice ios    arm64 arm64  appletvsimulator  18.0
build_slice ios    amd64 x86_64 appletvsimulator  18.0

lipo_slices iphonesimulator-universal  iphonesimulator-arm64  iphonesimulator-x86_64
lipo_slices macosx-universal           macosx-arm64           macosx-x86_64
lipo_slices appletvsimulator-universal appletvsimulator-arm64 appletvsimulator-x86_64

cp "$MODULE_DIR/cgo/module.modulemap" "$BUILD_DIR/include/module.modulemap"

rm -rf "$OUT"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/iphoneos-arm64/$LIB"             -headers "$BUILD_DIR/include" \
    -library "$BUILD_DIR/iphonesimulator-universal/$LIB"  -headers "$BUILD_DIR/include" \
    -library "$BUILD_DIR/macosx-universal/$LIB"           -headers "$BUILD_DIR/include" \
    -library "$BUILD_DIR/appletvos-arm64/$LIB"            -headers "$BUILD_DIR/include" \
    -library "$BUILD_DIR/appletvsimulator-universal/$LIB" -headers "$BUILD_DIR/include" \
    -output "$OUT"

# Xcode copies library-style xcframework headers into one shared include/ dir, where several
# module.modulemap files collide; re-package the slices as static frameworks instead.
python3 scripts/make-static-frameworks.py "$OUT" "$OUT" LibHysteria libhysteria.h

for slice in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64 tvos-arm64 tvos-arm64_x86_64-simulator; do
    if ! grep -q "<string>$slice</string>" "$OUT/Info.plist"; then
        echo "error: $OUT is missing the $slice slice" >&2
        exit 1
    fi
done
scripts/check-frameworks.sh LibHysteria

HYSTERIA="$(cd "$MODULE_DIR" && go list -m -f '{{.Version}}' github.com/apernet/hysteria/core/v2)"
{
    echo "libhysteria: $VERSION"
    echo "hysteria core/v2: $HYSTERIA"
    echo "go: $(go version)"
    echo "built: $(date -u +%FT%TZ)"
} > "$ROOT/Frameworks/LibHysteria.version"

echo "Built $OUT"
cat "$ROOT/Frameworks/LibHysteria.version"
