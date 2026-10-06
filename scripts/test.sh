#!/bin/sh
# Runs the package tests on macOS.
#
# One test binary holds every test target, and a binary can hold only one Go runtime: the Xray tests link
# LibXray's, so WireGuardKit links a C stub of its engine here (DVPNSDK_WIREGUARD_GO_STUB, Package.swift). No
# test starts a tunnel.
set -e

cd "$(dirname "$0")/.."
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

DVPNSDK_WIREGUARD_GO_STUB=1 swift test --scratch-path .build/test "$@"
