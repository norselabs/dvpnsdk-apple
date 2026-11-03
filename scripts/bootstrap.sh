#!/bin/bash
# Prepares a checkout: checks the lint tools and enables the git hooks. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
# scripts/check.sh accepts only the SwiftFormat and SwiftLint it pins. Homebrew installs only the newest release, so a
# pinned one comes from the tool's GitHub release.
# check_pin VARIABLE TOOL INSTALLED
check_pin() {
  local pinned
  pinned=$(sed -n "s/^$1=//p" scripts/check.sh)
  [[ $3 == "$pinned" ]] ||
    echo "! $2 $pinned is pinned in scripts/check.sh, ${3:-none} is installed: get it from its GitHub release" >&2
}
check_pin SWIFTFORMAT_VERSION swiftformat "$(swiftformat --version 2>/dev/null || true)"
check_pin SWIFTLINT_VERSION swiftlint "$(swiftlint version 2>/dev/null || true)"
git config core.hooksPath scripts/githooks
echo "✓ core.hooksPath = scripts/githooks"
