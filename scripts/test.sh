#!/bin/sh
# Runs the package tests on macOS. No test starts a tunnel.
set -e

cd "$(dirname "$0")/.."
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

swift test --scratch-path .build/test "$@"
