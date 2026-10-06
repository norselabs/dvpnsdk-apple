#!/bin/sh
# Packs the four engines in Frameworks/ as release assets and points Package.swift at them.
#
#   scripts/make-release-assets.sh <version>
#
# Writes .build/release/<version>/: <name>.xcframework.zip for each engine (what Package.swift downloads), plus
# <name>.licenses.json and <name>.version. Sets `binaryRelease` and the checksums in Package.swift. Upload every file
# of that directory to the GitHub release <version>, created on the commit that carries this Package.swift; until
# then, only a checkout with the engines in Frameworks/ resolves the package.
set -eu

[ $# -eq 1 ] || { echo "usage: $0 <version>" >&2; exit 2; }
cd "$(dirname "$0")/.."
version=$1
out=.build/release/$version
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

scripts/check-frameworks.sh
python3 scripts/gen-credits.py --check
rm -rf "$out"
mkdir -p "$out"
for name in LibXray LibHysteria HevSocks5Tunnel WireGuardKitGo; do
    # -y keeps the macOS slices' symlinks; -X leaves out extended attributes, so the zip depends on the files alone.
    (cd Frameworks && zip -qryX "../$out/$name.xcframework.zip" "$name.xcframework")
    cp "Frameworks/$name.licenses.json" "Frameworks/$name.version" "$out/"
    checksum=$(swift package compute-checksum "$out/$name.xcframework.zip")
    sed -i '' -E "s/^    \"$name\": \"[0-9a-f]*\",$/    \"$name\": \"$checksum\",/" Package.swift
    grep -q "\"$name\": \"$checksum\"" Package.swift || { echo "Package.swift has no checksum line for $name" >&2; exit 1; }
    echo "$name: $checksum"
done
sed -i '' -E "s/^let binaryRelease = \"[^\"]*\"$/let binaryRelease = \"$version\"/" Package.swift
grep -q "^let binaryRelease = \"$version\"$" Package.swift || { echo "Package.swift has no binaryRelease line" >&2; exit 1; }

echo "Wrote $out; Package.swift now downloads release $version. Upload:"
ls -1 "$out"
