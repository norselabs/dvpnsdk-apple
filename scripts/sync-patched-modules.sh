#!/bin/sh
# Generates the patched copies of Xray-core and REALITY that LibXray is built with, so it links no
# GPL or LGPL code and no config loader it does not use:
#
# - Xray-core without Shadowsocks 2022: upstream links github.com/sagernet/sing and sing-shadowsocks
#   (GPL-3.0-or-later) for it alone (proxy/shadowsocks_2022, common/singbridge); the SDK never uses
#   it (DVPNXRayCore renders VMess, VLESS and Trojan).
# - Xray-core without its YAML and TOML config loaders (main/yaml, main/toml): libXray passes JSON
#   only, and the loaders link two YAML libraries and go-toml.
# - REALITY without its fallback rate limiter: it is built on github.com/juju/ratelimit (LGPL-3.0),
#   and only a REALITY server uses it.
#
# Both copies stay MPL-2.0.
#
#   scripts/sync-patched-modules.sh <libXray source dir>
#
# writes <libXray source dir>/../Xray-core, where `build/main.py apple go local` looks for it, and
# ../REALITY next to it. Inputs, all committed: GoBridge/<module>/<module>.sum pins each version and
# its module hash (go.sum format), and GoBridge/<module>/*.patch is applied without fuzz. The Xray-core
# version must be the one libXray pins (DEFAULT_XRAY_CORE_VERSION), the REALITY version the one that
# Xray-core requires.
set -eu

[ $# -eq 1 ] || { echo "usage: $0 <libXray source dir>" >&2; exit 2; }
cd "$(dirname "$0")/.."
LIBXRAY=$(cd "$1" && pwd)
OUT=$(dirname "$LIBXRAY")
TAB=$(printf '\t')
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# pinned <sum file> <module>: prints the pinned version and hash.
pinned() {
    set -- $(cat "$1") "$2" "$1"
    [ "$#" -eq 5 ] && [ "$1" = "$4" ] || { echo "$5: want one line '$4 <version> h1:...'" >&2; exit 1; }
    echo "$2 $3"
}

# sync_module <module> <version> <hash> <patch dir> <destination> <removed dir>... -- <dropped require>...
sync_module() {
    mod=$1 version=$2 hash=$3 patches=$PWD/$4 dst=$5
    shift 5
    zip=$(cd "$tmp" && GOFLAGS= go mod download -json "$mod@$version" | sed -n 's/^[[:space:]]*"Zip": "\(.*\)",$/\1/p')
    [ -f "$zip" ] || { echo "$mod@$version: module zip not downloaded" >&2; exit 1; }

    # Unpack the module zip and recompute its go.sum hash (dirhash h1: sha256 over the sorted
    # "<sha256>  <name>" lines), so the input is checked against the pinned hash, not trusted.
    unpacked=$tmp/zip-$(basename "$dst")
    mkdir "$unpacked"
    unzip -q "$zip" -d "$unpacked"
    got=h1:$( (cd "$unpacked" && find . -type f -exec shasum -a 256 {} + |
        awk '{h=$1; sub(/^[^ ]+  \.\//, ""); printf "%s\t%s\n", $0, h}' | LC_ALL=C sort -t "$TAB" -k1,1 |
        awk -F "$TAB" '{printf "%s  %s\n", $2, $1}') | shasum -a 256 | cut -d' ' -f1 | xxd -r -p | base64)
    [ "$got" = "$hash" ] || { echo "$mod@$version: module hash $got, pinned $hash" >&2; exit 1; }

    # Library sources only: no tests, test scenarios, CI files or data files.
    new=$tmp/$(basename "$dst")
    rsync -a --exclude '*_test.go' --exclude '*.dat' --exclude /testing/ --exclude /.github/ \
        "$unpacked/$mod@$version/" "$new/"
    chmod -R u+w "$new"
    while [ $# -gt 0 ] && [ "$1" != -- ]; do rm -rf "${new:?}/$1"; shift; done
    [ $# -gt 0 ] && shift
    # No fuzz: a hunk whose context moved fails here instead of landing in the wrong place.
    applied=
    for patch in "$patches"/*.patch; do
        (cd "$new" && patch -p1 -F0 -N --no-backup-if-mismatch --quiet <"$patch") ||
            { echo "$(basename "$patch") does not apply to $mod $version without fuzz: update the patch" >&2; exit 1; }
        if find "$new" -name '*.rej' -o -name '*.orig' | grep .; then
            echo "$(basename "$patch") left rejects" >&2
            exit 1
        fi
        applied="$applied $(basename "$patch")"
    done
    for req in "$@"; do
        (cd "$new" && GOFLAGS= go mod edit -droprequire="$req" &&
            grep -v "^$req " go.sum > go.sum.tmp && mv go.sum.tmp go.sum)
    done

    rm -rf "$dst"
    mv "$new" "$dst"
    echo "$dst: $mod $version ($hash),$applied applied"
}

XRAY=github.com/xtls/xray-core
set -- $(pinned GoBridge/xray-core/xray-core.sum "$XRAY")
XRAY_VERSION=$1 XRAY_HASH=$2
LIBXRAY_VERSION=$(sed -n 's/^DEFAULT_XRAY_CORE_VERSION = "\(.*\)"$/\1/p' "$LIBXRAY/build/app/build.py")
[ "$LIBXRAY_VERSION" = "$XRAY_VERSION" ] || {
    echo "libXray pins $XRAY ${LIBXRAY_VERSION:-(not found)} but GoBridge/xray-core/xray-core.sum pins $XRAY_VERSION:" >&2
    echo "update the pins and check that the patches still apply" >&2
    exit 1
}
sync_module "$XRAY" "$XRAY_VERSION" "$XRAY_HASH" GoBridge/xray-core "$OUT/Xray-core" \
    proxy/shadowsocks_2022 common/singbridge main/toml main/yaml -- github.com/sagernet/sing \
    github.com/sagernet/sing-shadowsocks github.com/juju/ratelimit github.com/ghodss/yaml github.com/pelletier/go-toml

REALITY=github.com/xtls/reality
set -- $(pinned GoBridge/reality/reality.sum "$REALITY")
REALITY_VERSION=$1 REALITY_HASH=$2
grep -q "^[[:space:]]*$REALITY $REALITY_VERSION\$" "$OUT/Xray-core/go.mod" || {
    echo "Xray-core does not require $REALITY $REALITY_VERSION, which GoBridge/reality/reality.sum pins: update the pin" >&2
    exit 1
}
sync_module "$REALITY" "$REALITY_VERSION" "$REALITY_HASH" GoBridge/reality "$OUT/REALITY" \
    -- github.com/juju/ratelimit

# Imports and module lines only: some comments name other projects' modules.
if grep -rl -E --include='*.go' \
    '"github.com/(sagernet/|juju/ratelimit)|"github.com/xtls/xray-core/(proxy/shadowsocks_2022|common/singbridge)' \
    "$OUT/Xray-core" "$OUT/REALITY" ||
    grep -l -E '(^|[[:space:]])github.com/(sagernet/|juju/ratelimit)' \
    "$OUT/Xray-core/go.mod" "$OUT/Xray-core/go.sum" "$OUT/REALITY/go.mod" "$OUT/REALITY/go.sum"; then
    echo "the files above still reference sing, sing-shadowsocks, juju/ratelimit or the removed packages: extend the patches" >&2
    exit 1
fi
