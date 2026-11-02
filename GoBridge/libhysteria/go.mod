module github.com/norselabs/libhysteria

go 1.26.0

toolchain go1.27.3

// Hysteria is pinned to release app/v2.13.0 (commit ca8fbd8; the core/extras modules carry the
// matching v2.13.0 tags). extras/go.mod uses "replace ../core", which Go ignores in dependencies,
// so core is replaced explicitly to the same tag.
require (
	github.com/apernet/hysteria/core/v2 v2.13.0
	github.com/apernet/hysteria/extras/v2 v2.13.0
	github.com/txthinking/socks5 v0.0.0-20230325130024-4230056ae301
)

require (
	github.com/andybalholm/brotli v1.1.0 // indirect
	github.com/apernet/quic-go v0.63.1-0.20261004180939-a10df75c260c // indirect
	github.com/klauspost/compress v1.17.9 // indirect
	github.com/patrickmn/go-cache v2.1.0+incompatible // indirect
	github.com/quic-go/qpack v0.6.0 // indirect
	github.com/refraction-networking/utls v1.8.2 // indirect
	github.com/stretchr/objx v0.5.3 // indirect
	github.com/stretchr/testify v1.12.1 // indirect
	github.com/txthinking/runnergroup v0.0.0-20210608031112-152c7c4432bf // indirect
	go.yaml.in/yaml/v3 v3.0.5 // indirect
	golang.org/x/crypto v0.54.0 // indirect
	golang.org/x/exp v0.0.0-20240506185415-9bf2ced13842 // indirect
	golang.org/x/net v0.57.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.40.0 // indirect
)

replace github.com/apernet/hysteria/core/v2 => github.com/apernet/hysteria/core/v2 v2.13.0
