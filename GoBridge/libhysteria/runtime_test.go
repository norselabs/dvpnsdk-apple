package libhysteria

import (
	"errors"
	"io"
	"net"
	"os"
	"syscall"
	"testing"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
)

// A failed proxied connection names the destination the user visits, which no output may hold (README › Logs).
func TestFailedConnectionsWriteNothing(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	server := newSOCKS5Server(failingClient{}, SOCKS5Config{UDP: true})
	go func() { _ = server.Serve(listener) }()

	written := stderrOf(t, func() {
		// CONNECT to 203.0.113.7:443, then UDP ASSOCIATE: the Hysteria client fails both.
		if reply := request(t, listener.Addr(), []byte{5, 1, 0, 1, 203, 0, 113, 7, 1, 187}); reply != 4 {
			t.Errorf("TCP reply %d, want 4 (host unreachable)", reply)
		}
		if reply := request(t, listener.Addr(), []byte{5, 3, 0, 1, 0, 0, 0, 0, 0, 0}); reply != 1 {
			t.Errorf("UDP reply %d, want 1 (server failure)", reply)
		}
	})
	if written != "" {
		t.Fatalf("standard error got %q", written)
	}
}

// request sends one SOCKS5 request without authentication and returns the reply's code once the server has closed the
// connection, which it does after reporting the connection's error.
func request(t *testing.T, server net.Addr, req []byte) byte {
	t.Helper()
	conn, err := net.Dial("tcp", server.String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	method := make([]byte, 2)
	if _, err := conn.Write([]byte{5, 1, 0}); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(conn, method); err != nil || method[1] != 0 {
		t.Fatalf("negotiation: %v, %v", method, err)
	}
	reply := make([]byte, 2)
	if _, err := conn.Write(req); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatal(err)
	}
	if _, err := io.Copy(io.Discard, conn); err != nil {
		t.Fatal(err)
	}
	return reply[1]
}

// stderrOf returns what f writes to the process's standard error, file descriptor 2, which the log package and the
// runtime write to as well.
func stderrOf(t *testing.T, f func()) (written string) {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	saved, err := syscall.Dup(2)
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.Dup2(int(w.Fd()), 2); err != nil {
		t.Fatal(err)
	}
	read := make(chan []byte)
	go func() {
		b, _ := io.ReadAll(r)
		read <- b
	}()
	defer func() {
		_ = syscall.Dup2(saved, 2)
		_ = syscall.Close(saved)
		_ = w.Close()
		written = string(<-read)
	}()
	f()
	return
}

type failingClient struct{}

func (failingClient) TCP(addr string) (net.Conn, error) {
	return nil, errors.New("dial tcp " + addr + ": connection refused")
}

func (failingClient) UDP() (client.HyUDPConn, error) {
	return nil, errors.New("UDP not enabled on the server")
}

func (failingClient) Close() error { return nil }
