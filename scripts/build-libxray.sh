#!/bin/sh
# Builds Frameworks/LibXray.xcframework from XTLS/libXray (cgo c-archive mode), on the copies of
# Xray-core (without Shadowsocks 2022 and the YAML and TOML config loaders) and REALITY (without its
# fallback rate limiter) that scripts/sync-patched-modules.sh generates: upstream links GPL-3.0 and
# LGPL-3.0 code for the first two. GoBridge/nogpl checks the licence of every linked module before
# the build and writes their inventory (Frameworks/LibXray.licenses.json, for an app's licences list),
# and scripts/check-frameworks.sh checks the binaries after it.
#
# The cgo build is used instead of gomobile because gomobile cannot target tvOS.
# Output slices: ios-arm64, ios-arm64_x86_64-simulator, macos-arm64_x86_64,
# tvos-arm64, tvos-arm64_x86_64-simulator. Swift imports the result as `LibXray`
# and talks to it through the C API (`CGoInvoke` / `CGoFree`).
#
# Requirements: git, python3, go (any recent version; the pinned toolchain is
# downloaded automatically), Xcode with the iOS and tvOS simulator runtimes.
set -eu

cd "$(dirname "$0")/.."

LIBXRAY_REF="${LIBXRAY_REF:-v26.9.9}"
SRC="${LIBXRAY_SRC:-.build/libxray-src}"
OUT="Frameworks/LibXray.xcframework"

export GOTOOLCHAIN="${GO_TOOLCHAIN:-go1.27.1}"
export GOFLAGS="${GOFLAGS:--mod=mod}"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$(go env GOPATH)/bin"
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

if [ ! -d "$SRC/.git" ]; then
    git clone --quiet https://github.com/XTLS/libXray.git "$SRC"
fi
git -C "$SRC" fetch --quiet --tags origin
# The local build edits go.mod and go.sum (the replace, then go mod tidy): start from the tag.
git -C "$SRC" reset --quiet --hard
git -C "$SRC" checkout --quiet "$LIBXRAY_REF"
git -C "$SRC" clean -fdxq -e LibXray.xcframework || true

scripts/sync-patched-modules.sh "$SRC"

# The graph the build compiles: Xray-core and REALITY replaced by the copies above. `local` makes
# libXray replace Xray-core itself and tidy, and it restores go.mod and go.sum afterwards to what
# they were before it started, so the REALITY replacement made here holds for the build.
( cd "$SRC" && go mod edit -replace=github.com/xtls/xray-core=../Xray-core -replace=github.com/xtls/reality=../REALITY &&
    go mod tidy )
go -C GoBridge/nogpl run . -C "$(cd "$SRC" && pwd)" -inventory "$PWD/Frameworks/LibXray.licenses.json" -main-version "$LIBXRAY_REF" \
    -replace github.com/xtls/xray-core=../Xray-core -replace github.com/xtls/reality=../REALITY ./cgo_bridge

echo "Building libXray $LIBXRAY_REF ($(git -C "$SRC" rev-parse --short HEAD)) with $GOTOOLCHAIN"
( cd "$SRC" && python3 build/main.py apple go local )
git -C "$SRC" checkout --quiet -- go.mod go.sum

rm -rf "$OUT"
cp -R "$SRC/LibXray.xcframework" "$OUT"

# Xcode copies library-style xcframework headers into one shared include/ dir, where several
# module.modulemap files collide; re-package the slices as static frameworks instead.
python3 scripts/make-static-frameworks.py "$OUT" "$OUT" LibXray libXray.h

for slice in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64 tvos-arm64 tvos-arm64_x86_64-simulator; do
    if ! grep -q "<string>$slice</string>" "$OUT/Info.plist"; then
        echo "error: $OUT is missing the $slice slice" >&2
        exit 1
    fi
done
scripts/check-frameworks.sh LibXray

XRAY_CORE="$(cd "$SRC" && go list -m -f '{{.Version}}' github.com/xtls/xray-core)"
REALITY="$(cd "$SRC" && go list -m -f '{{.Version}}' github.com/xtls/reality)"
{
    echo "libXray: $LIBXRAY_REF ($(git -C "$SRC" rev-parse --short HEAD))"
    echo "xray-core: $XRAY_CORE without Shadowsocks 2022 and the YAML and TOML config loaders (GoBridge/xray-core)"
    echo "reality: $REALITY without the fallback rate limiter (GoBridge/reality)"
    echo "go: $(go version)"
    echo "built: $(date -u +%FT%TZ)"
} > Frameworks/LibXray.version

echo "Built $OUT"
cat Frameworks/LibXray.version
