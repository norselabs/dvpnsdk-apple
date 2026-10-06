package libhysteria

import (
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
	"github.com/apernet/hysteria/extras/v2/obfs"
)

// Config is the JSON contract with the Swift side (DVPNHysteriaCore.HysteriaConfiguration).
// Keep the field names and shapes in sync; unknown keys (e.g. "name") are ignored.
type Config struct {
	Server    string           `json:"server"`
	Port      uint16           `json:"port"`
	Auth      string           `json:"auth"`
	TLS       TLSConfig        `json:"tls"`
	Obfs      *ObfsConfig      `json:"obfs,omitempty"`
	Bandwidth *BandwidthConfig `json:"bandwidth,omitempty"`
	QUIC      *QUICConfig      `json:"quic,omitempty"`
	FastOpen  bool             `json:"fastOpen"`
	Lazy      bool             `json:"lazy"`
	SOCKS5    SOCKS5Config     `json:"socks5"`
}

type TLSConfig struct {
	SNI       string `json:"sni,omitempty"`
	Insecure  bool   `json:"insecure"`
	PinSHA256 string `json:"pinSHA256,omitempty"`
}

type ObfsConfig struct {
	Type     string `json:"type"`
	Password string `json:"password"`
}

type BandwidthConfig struct {
	UpMbps   uint64 `json:"upMbps,omitempty"`
	DownMbps uint64 `json:"downMbps,omitempty"`
}

type QUICConfig struct {
	InitStreamReceiveWindow uint64 `json:"initStreamReceiveWindow,omitempty"`
	MaxStreamReceiveWindow  uint64 `json:"maxStreamReceiveWindow,omitempty"`
	InitConnReceiveWindow   uint64 `json:"initConnReceiveWindow,omitempty"`
	MaxConnReceiveWindow    uint64 `json:"maxConnReceiveWindow,omitempty"`
	MaxIdleTimeoutSec       int    `json:"maxIdleTimeoutSec,omitempty"`
	KeepAlivePeriodSec      int    `json:"keepAlivePeriodSec,omitempty"`
	DisablePathMTUDiscovery bool   `json:"disablePathMTUDiscovery"`
}

type SOCKS5Config struct {
	Listen string `json:"listen"`
	UDP    bool   `json:"udp"`
	// When both are set, the server accepts only these credentials: any process on the device can
	// reach a loopback port, so the extension makes new ones for every start.
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
}

const (
	obfsTypeSalamander = "salamander"
	salamanderMinPSK   = 4

	defaultPort         = 443
	defaultSOCKS5Listen = "[::1]:8080"

	// Receive windows sized for a 50 MB iOS network extension; Hysteria's own defaults
	// (8 MiB / 20 MiB) leave too little headroom next to the Go heap and hev-socks5-tunnel.
	defaultStreamReceiveWindow    = 1 << 20
	defaultMaxStreamReceiveWindow = 4 << 20
	defaultConnReceiveWindow      = 5 << 19
	defaultMaxConnReceiveWindow   = 10 << 20
	defaultMaxIdleTimeout         = 30 * time.Second
	defaultKeepAlivePeriod        = 10 * time.Second
)

// ParseConfig decodes and validates the JSON configuration, applying defaults.
func ParseConfig(text string) (*Config, error) {
	var c Config
	if err := json.Unmarshal([]byte(text), &c); err != nil {
		return nil, fmt.Errorf("invalid hysteria config: %w", err)
	}
	if err := c.validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

func (c *Config) validate() error {
	c.Server = strings.TrimSpace(c.Server)
	if c.Server == "" {
		return errors.New("hysteria config: server is required")
	}
	if c.Port == 0 {
		c.Port = defaultPort
	}
	if strings.TrimSpace(c.SOCKS5.Listen) == "" {
		c.SOCKS5.Listen = defaultSOCKS5Listen
	}
	if _, _, err := net.SplitHostPort(c.SOCKS5.Listen); err != nil {
		return fmt.Errorf("hysteria config: invalid socks5.listen %q: %w", c.SOCKS5.Listen, err)
	}
	if (c.SOCKS5.Username == "") != (c.SOCKS5.Password == "") {
		return errors.New("hysteria config: socks5 needs both a username and a password, or neither")
	}
	if c.Obfs != nil {
		if !strings.EqualFold(c.Obfs.Type, obfsTypeSalamander) {
			return fmt.Errorf("hysteria config: unsupported obfs type %q", c.Obfs.Type)
		}
		if len(c.Obfs.Password) < salamanderMinPSK {
			return fmt.Errorf("hysteria config: obfs password must be at least %d bytes", salamanderMinPSK)
		}
	}
	if c.TLS.PinSHA256 != "" {
		normalized := normalizeCertHash(c.TLS.PinSHA256)
		if _, err := hex.DecodeString(normalized); err != nil || len(normalized) != sha256.Size*2 {
			return fmt.Errorf("hysteria config: tls.pinSHA256 is not a hex SHA-256 digest")
		}
		c.TLS.PinSHA256 = normalized
	}
	return nil
}

// toCoreConfig maps the JSON configuration onto core/v2's client.Config.
// Mirrors app/cmd/client.go; zero QUIC values are filled by core's verifyAndFill.
func (c *Config) toCoreConfig() (*client.Config, error) {
	addr, err := net.ResolveUDPAddr("udp", net.JoinHostPort(c.Server, strconv.Itoa(int(c.Port))))
	if err != nil {
		return nil, fmt.Errorf("resolve %s: %w", c.Server, err)
	}

	sni := c.TLS.SNI
	if sni == "" {
		sni = c.Server
	}
	tlsConfig := client.TLSConfig{
		ServerName:         sni,
		InsecureSkipVerify: c.TLS.Insecure,
	}
	if c.TLS.PinSHA256 != "" {
		tlsConfig.InsecureSkipVerify = true
		tlsConfig.VerifyPeerCertificate = pinVerifier(c.TLS.PinSHA256)
	}

	quicConfig := client.QUICConfig{
		InitialStreamReceiveWindow:     defaultStreamReceiveWindow,
		MaxStreamReceiveWindow:         defaultMaxStreamReceiveWindow,
		InitialConnectionReceiveWindow: defaultConnReceiveWindow,
		MaxConnectionReceiveWindow:     defaultMaxConnReceiveWindow,
		MaxIdleTimeout:                 defaultMaxIdleTimeout,
		KeepAlivePeriod:                defaultKeepAlivePeriod,
	}
	if q := c.QUIC; q != nil {
		if q.InitStreamReceiveWindow != 0 {
			quicConfig.InitialStreamReceiveWindow = q.InitStreamReceiveWindow
		}
		if q.MaxStreamReceiveWindow != 0 {
			quicConfig.MaxStreamReceiveWindow = q.MaxStreamReceiveWindow
		}
		if q.InitConnReceiveWindow != 0 {
			quicConfig.InitialConnectionReceiveWindow = q.InitConnReceiveWindow
		}
		if q.MaxConnReceiveWindow != 0 {
			quicConfig.MaxConnectionReceiveWindow = q.MaxConnReceiveWindow
		}
		if q.MaxIdleTimeoutSec > 0 {
			quicConfig.MaxIdleTimeout = time.Duration(q.MaxIdleTimeoutSec) * time.Second
		}
		if q.KeepAlivePeriodSec > 0 {
			quicConfig.KeepAlivePeriod = time.Duration(q.KeepAlivePeriodSec) * time.Second
		}
		quicConfig.DisablePathMTUDiscovery = q.DisablePathMTUDiscovery
	}

	var bandwidth client.BandwidthConfig
	if b := c.Bandwidth; b != nil {
		bandwidth.MaxTx = mbpsToBytesPerSecond(b.UpMbps)
		bandwidth.MaxRx = mbpsToBytesPerSecond(b.DownMbps)
	}

	var obfsPassword []byte
	if c.Obfs != nil {
		obfsPassword = []byte(c.Obfs.Password)
	}

	return &client.Config{
		ConnFactory:     &udpConnFactory{obfsPassword: obfsPassword},
		ServerAddr:      addr,
		Auth:            c.Auth,
		TLSConfig:       tlsConfig,
		QUICConfig:      quicConfig,
		BandwidthConfig: bandwidth,
		FastOpen:        c.FastOpen,
	}, nil
}

func mbpsToBytesPerSecond(mbps uint64) uint64 {
	return mbps * 1_000_000 / 8
}

// udpConnFactory opens the UDP socket the QUIC connection rides on, optionally wrapped in
// Salamander obfuscation.
type udpConnFactory struct {
	obfsPassword []byte
}

func (f *udpConnFactory) New(addr net.Addr) (net.PacketConn, error) {
	conn, err := net.ListenUDP("udp", nil)
	if err != nil {
		return nil, err
	}
	if len(f.obfsPassword) == 0 {
		return conn, nil
	}
	wrapped, err := obfs.WrapPacketConnSalamander(conn, f.obfsPassword)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	return wrapped, nil
}

// normalizeCertHash mirrors hysteria's app: drop separators, lowercase.
func normalizeCertHash(hash string) string {
	r := strings.ToLower(hash)
	r = strings.ReplaceAll(r, ":", "")
	r = strings.ReplaceAll(r, "-", "")
	r = strings.ReplaceAll(r, " ", "")
	return r
}

func pinVerifier(expected string) func(rawCerts [][]byte, verifiedChains [][]*x509.Certificate) error {
	return func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
		for _, cert := range rawCerts {
			sum := sha256.Sum256(cert)
			if hex.EncodeToString(sum[:]) == expected {
				return nil
			}
		}
		return errors.New("no certificate matches the pinned SHA-256 digest")
	}
}

// tlsMinVersion documents the floor Hysteria 2 uses (QUIC requires TLS 1.3).
var _ = tls.VersionTLS13

// authFunc checks the SOCKS5 credentials in constant time, or is nil (no authentication) when none are set.
func (c SOCKS5Config) authFunc() func(username, password string) bool {
	if c.Username == "" {
		return nil
	}
	wantUser, wantPass := []byte(c.Username), []byte(c.Password)
	return func(username, password string) bool {
		userOK := subtle.ConstantTimeCompare([]byte(username), wantUser) == 1
		passOK := subtle.ConstantTimeCompare([]byte(password), wantPass) == 1
		return userOK && passOK
	}
}
