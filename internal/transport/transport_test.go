package transport

import (
	"context"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/mock"
)

func shortSocket(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "md")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return filepath.Join(dir, "d.sock")
}

func startTransport(t *testing.T) (*Transport, string, context.CancelFunc) {
	t.Helper()
	sock := shortSocket(t)
	p, err := mock.New(config.Device{Name: "loop", Type: "mock"})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Open(context.Background()); err != nil {
		t.Fatal(err)
	}
	tr := New("loop", sock, p, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := tr.Start(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	go tr.Serve(ctx)
	return tr, sock, cancel
}

func TestTransportEchoes(t *testing.T) {
	tr, sock, cancel := startTransport(t)
	defer cancel()
	defer tr.Close()

	conn, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte("hey")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	_ = conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(conn, buf); err != nil {
		t.Fatalf("echo: %v", err)
	}
	if string(buf) != "hey" {
		t.Fatalf("got %q, want hey", buf)
	}
}

func TestTransportRefusesSecondGuest(t *testing.T) {
	tr, sock, cancel := startTransport(t)
	defer cancel()
	defer tr.Close()

	c1, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c1.Close()
	// ensure c1 is the active guest
	if _, err := c1.Write([]byte("x")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 1)
	_ = c1.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(c1, buf); err != nil {
		t.Fatalf("first guest echo: %v", err)
	}

	// second guest should be refused: the connection is closed by the server
	c2, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	_ = c2.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := c2.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("second guest: want EOF (refused), got %v", err)
	}
}
