// Package libhysteria embeds the Hysteria 2 client (github.com/apernet/hysteria core/v2) behind a
// local SOCKS5 server so an Apple packet tunnel extension can front it with hev-socks5-tunnel.
//
// The C entry points live in ./cgo and are built with `go build -buildmode=c-archive` into
// LibHysteria.xcframework by scripts/build-libhysteria.sh. Go allows one runtime per process, so
// this library must only be linked into the Hysteria network extension.
package libhysteria
