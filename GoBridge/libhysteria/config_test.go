package libhysteria

import (
	"os"
	"testing"
)

func TestParseFixtureMatchesSwiftContract(t *testing.T) {
	data, err := os.ReadFile("testdata/config.json")
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := ParseConfig(string(data))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Server != "203.0.113.10" || cfg.Port != 8443 || cfg.Auth != "secret" {
		t.Fatalf("unexpected server fields: %+v", cfg)
	}
	if cfg.Obfs == nil || cfg.Obfs.Password != "salamander-pw" {
		t.Fatalf("obfs not decoded: %+v", cfg.Obfs)
	}
	if cfg.TLS.PinSHA256 != "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789" {
		t.Fatalf("pin not normalized: %q", cfg.TLS.PinSHA256)
	}
	if cfg.SOCKS5.Listen != "[::1]:8080" || !cfg.SOCKS5.UDP || cfg.SOCKS5.Username != "local-user" || cfg.SOCKS5.Password != "local-pass" {
		t.Fatalf("socks5 not decoded: %+v", cfg.SOCKS5)
	}
}

func TestToCoreConfig(t *testing.T) {
	cfg, err := ParseConfig(`{"server":"127.0.0.1","port":8443,"auth":"pw","tls":{"insecure":true},
		"bandwidth":{"upMbps":8,"downMbps":80},"quic":{"maxIdleTimeoutSec":45},"fastOpen":true,"socks5":{"listen":"[::1]:1080","udp":true}}`)
	if err != nil {
		t.Fatal(err)
	}
	core, err := cfg.toCoreConfig()
	if err != nil {
		t.Fatal(err)
	}
	if core.ServerAddr.String() != "127.0.0.1:8443" {
		t.Fatalf("server addr: %s", core.ServerAddr)
	}
	if core.TLSConfig.ServerName != "127.0.0.1" || !core.TLSConfig.InsecureSkipVerify {
		t.Fatalf("tls: %+v", core.TLSConfig)
	}
	if core.BandwidthConfig.MaxTx != 1_000_000 || core.BandwidthConfig.MaxRx != 10_000_000 {
		t.Fatalf("bandwidth: %+v", core.BandwidthConfig)
	}
	if core.QUICConfig.MaxIdleTimeout.Seconds() != 45 || core.QUICConfig.KeepAlivePeriod != defaultKeepAlivePeriod {
		t.Fatalf("quic: %+v", core.QUICConfig)
	}
	if !core.FastOpen {
		t.Fatal("fastOpen not mapped")
	}
}

func TestValidation(t *testing.T) {
	cases := map[string]string{
		"missing server":    `{"auth":"x"}`,
		"bad obfs type":     `{"server":"h","obfs":{"type":"xplus","password":"1234"}}`,
		"short obfs psk":    `{"server":"h","obfs":{"type":"salamander","password":"abc"}}`,
		"bad pin":           `{"server":"h","tls":{"pinSHA256":"zz"}}`,
		"bad socks5 listen": `{"server":"h","socks5":{"listen":"nope"}}`,
		"socks5 user only":  `{"server":"h","socks5":{"listen":"[::1]:1080","username":"u"}}`,
		"not json":          `{`,
	}
	for name, text := range cases {
		if _, err := ParseConfig(text); err == nil {
			t.Errorf("%s: expected error", name)
		}
	}

	cfg, err := ParseConfig(`{"server":"example.com","name":"ignored"}`)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Port != 443 || cfg.SOCKS5.Listen != "[::1]:8080" {
		t.Fatalf("defaults not applied: %+v", cfg)
	}
}

func TestStartRejectsInvalidConfigAndStopIsIdempotent(t *testing.T) {
	if err := Start(`{"server":""}`); err == nil {
		t.Fatal("expected error for empty server")
	}
	if IsRunning() {
		t.Fatal("must not be running")
	}
	if err := Stop(); err != nil {
		t.Fatalf("stop without start: %v", err)
	}
	if Version() == "" {
		t.Fatal("version must not be empty")
	}
}

func TestSOCKS5CredentialsAreCheckedWhenSet(t *testing.T) {
	cfg, err := ParseConfig(`{"server":"h","socks5":{"listen":"[::1]:1080","udp":true,"username":"user","password":"secret"}}`)
	if err != nil {
		t.Fatal(err)
	}
	check := cfg.SOCKS5.authFunc()
	if check == nil {
		t.Fatal("credentials set, but no authentication")
	}
	if !check("user", "secret") {
		t.Error("the right credentials are refused")
	}
	for _, wrong := range [][2]string{{"user", "wrong"}, {"other", "secret"}, {"", ""}} {
		if check(wrong[0], wrong[1]) {
			t.Errorf("wrong credentials %q accepted", wrong)
		}
	}

	open, err := ParseConfig(`{"server":"h"}`)
	if err != nil {
		t.Fatal(err)
	}
	if open.SOCKS5.authFunc() != nil {
		t.Error("no credentials set, but authentication required")
	}
}
