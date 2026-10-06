#!/bin/bash
# The check to run before pushing: formatting, lint, the engines' licence checks, then a build and the
# tests.
#
#   scripts/check.sh [--fix] [--platforms]
#
#   --fix       format with SwiftFormat before checking
#   --platforms compiles every target for iOS Simulator, macOS and tvOS Simulator (scripts/build-platforms.sh)
#
# Logs go to .build/check/. WireGuardKit's sources stay as upstream wrote them: lint skips them.
set -euo pipefail

cd "$(dirname "$0")/.."
fix=false
platforms=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --fix) fix=true ;;
    --platforms) platforms=true ;;
    *) echo "usage: $0 [--fix] [--platforms]" >&2; exit 2 ;;
  esac
  shift
done
if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
LOGS=.build/check
mkdir -p "$LOGS"

step() { step_started=$SECONDS; printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
pass() { printf '\033[32m✓ %s\033[0m (%ss)\n' "$*" $((SECONDS - step_started)); }

step "Format"
$fix && swiftformat Sources Tests --quiet
swiftformat Sources Tests --lint --quiet || fail "SwiftFormat found unformatted code: run scripts/check.sh --fix"
pass "SwiftFormat"

step "Lint"
swiftlint lint --strict --quiet || fail "SwiftLint found violations (each rule's message says what to do)"
pass "SwiftLint"

step "Go"
[[ -z "$(gofmt -l GoBridge)" ]] || fail "gofmt found unformatted Go code: run gofmt -w GoBridge"
{ go -C GoBridge/nogpl vet ./... && go -C GoBridge/nogpl test ./...; } > "$LOGS/nogpl.log" 2>&1 || { cat "$LOGS/nogpl.log" >&2; fail "GoBridge/nogpl vet or tests failed"; }
scripts/check-frameworks.sh > "$LOGS/frameworks.log" 2>&1 || { cat "$LOGS/frameworks.log" >&2; fail "a binary framework is missing, incomplete or links GPL or LGPL code"; }
pass "gofmt, GoBridge/nogpl tests, the binary frameworks complete and without GPL or LGPL code"

step "Build and test"
scripts/test.sh > "$LOGS/test.log" 2>&1 || { grep -E 'error:|failed' "$LOGS/test.log" | sort -u | head -20 >&2; fail "tests failed, see .build/check/test.log"; }
summary=$(grep -oE 'Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)' "$LOGS/test.log" | tail -1)
pass "${summary:-$(grep -E 'Executed [0-9]+ tests' "$LOGS/test.log" | tail -1 | sed 's/^[[:space:]]*//')}"

step "Credits"
python3 scripts/gen-credits.py --check || fail "CREDITS.md does not list what the package carries and links: run scripts/gen-credits.py"
pass "CREDITS.md is current"

if $platforms; then
  step "Platforms"
  scripts/build-platforms.sh > "$LOGS/platforms.log" 2>&1 || { tail -20 "$LOGS/platforms.log" >&2; fail "platform builds failed, see .build/check/platforms.log"; }
  pass "iOS Simulator, macOS and tvOS Simulator build"
fi

printf '\n'
step_started=0
pass "All checks passed"
