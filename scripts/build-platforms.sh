#!/bin/sh
# Compiles every target for iOS Simulator, macOS and tvOS Simulator with xcodebuild, which, unlike
# `swift build`, catches binary frameworks whose headers collide.
set -eu

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# build_for NAME XCODE_DESTINATION
build_for() {
    name="$1"; destination="$2"
    echo "==> $name ($destination)"
    log=".build/xcode-$name.log"
    if ! xcodebuild build \
        -scheme DVPNSDK-Package \
        -destination "$destination" \
        -derivedDataPath ".build/xcode-$name" \
        -skipMacroValidation -skipPackagePluginValidation \
        > "$log" 2>&1; then
        grep -E "error|Multiple commands" "$log" | head -20 >&2
        echo "error: $name build failed (full log: $log)" >&2
        exit 1
    fi
}

build_for ios-sim  'generic/platform=iOS Simulator'
build_for macos    'platform=macOS'
build_for tvos-sim 'generic/platform=tvOS Simulator'

echo "All platforms built."
