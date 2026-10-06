#!/bin/bash
# Prepares a checkout: checks the lint tools and enables the git hooks. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in swiftformat swiftlint; do
  command -v "$tool" >/dev/null || echo "! $tool is missing: brew install $tool" >&2
done
git config core.hooksPath scripts/githooks
echo "✓ core.hooksPath = scripts/githooks"
