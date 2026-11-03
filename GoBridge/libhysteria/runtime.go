package libhysteria

import (
	"errors"
	"fmt"
	"log"
	"net"
	"sync"

	"github.com/apernet/hysteria/core/v2/client"
	"github.com/norselabs/libhysteria/internal/socks5"
)

// version is stamped by the build script through -ldflags "-X ...libhysteria.version=".
var version = "dev"

var (
	mu      sync.Mutex
	current *instance
)

type instance struct {
	client   client.Client
	listener net.Listener
	done     chan struct{}
}

// Start parses configJSON, connects to the Hysteria server (unless lazy) and starts a SOCKS5
// server on socks5.listen. It returns once the SOCKS5 listener accepts connections; a failed
// QUIC handshake is returned as an error. Only one instance may run per process.
func Start(configJSON string) error {
	mu.Lock()
	defer mu.Unlock()

	if current != nil {
		return errors.New("hysteria is already running")
	}

	cfg, err := ParseConfig(configJSON)
	if err != nil {
		return err
	}

	initMemory()

	hyClient, err := client.NewReconnectableClient(
		cfg.toCoreConfig,
		func(_ client.Client, info *client.HandshakeInfo, count int) {
			log.Printf("libhysteria: connected to %s (udp=%v tx=%d attempt=%d)", info.ServerAddr, info.UDPEnabled, info.Tx, count)
		},
		cfg.Lazy,
	)
	if err != nil {
		return fmt.Errorf("hysteria connect: %w", err)
	}

	listener, err := net.Listen("tcp", cfg.SOCKS5.Listen)
	if err != nil {
		_ = hyClient.Close()
		return fmt.Errorf("socks5 listen on %s: %w", cfg.SOCKS5.Listen, err)
	}

	server := newSOCKS5Server(hyClient, cfg.SOCKS5)
	inst := &instance{client: hyClient, listener: listener, done: make(chan struct{})}
	go func() {
		defer close(inst.done)
		if err := server.Serve(listener); err != nil {
			log.Printf("libhysteria: socks5 server stopped: %v", err)
		}
	}()

	current = inst
	log.Printf("libhysteria %s: socks5 listening on %s", version, listener.Addr())
	return nil
}

// Stop closes the SOCKS5 listener and the Hysteria client. Safe to call when nothing runs.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()

	if current == nil {
		return nil
	}
	inst := current
	current = nil

	listenErr := inst.listener.Close()
	clientErr := inst.client.Close()
	<-inst.done
	stopMemory()

	return errors.Join(listenErr, clientErr)
}

// IsRunning reports whether Start succeeded and Stop has not been called since.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return current != nil
}

// Version returns the libhysteria build version.
func Version() string {
	return version
}

// newSOCKS5Server builds the SOCKS5 server Start runs, which the tests build too.
func newSOCKS5Server(hyClient client.Client, c SOCKS5Config) *socks5.Server {
	return &socks5.Server{
		HyClient:    hyClient,
		AuthFunc:    c.authFunc(),
		DisableUDP:  !c.UDP,
		EventLogger: silentLogger{},
	}
}

// silentLogger drops the SOCKS5 server's connection events: they name the destinations the user visits, and their
// errors quote them (README › Logs).
type silentLogger struct{}

func (silentLogger) TCPRequest(addr net.Addr, reqAddr string) {}

func (silentLogger) TCPError(addr net.Addr, reqAddr string, err error) {}

func (silentLogger) UDPRequest(addr net.Addr) {}

func (silentLogger) UDPError(addr net.Addr, err error) {}
