package daemon

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
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/mock"
)

func shortRunDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "mdrun")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

func testRegistry() *plugin.Registry {
	r := plugin.NewRegistry()
	r.Register("mock", mock.New)
	return r
}

func TestDaemonRunsAndCleansUp(t *testing.T) {
	runDir := shortRunDir(t)
	cfg := &config.Config{Devices: []config.Device{
		{Name: "loop", Type: "mock", Socket: "loop.sock"},
	}}
	d := New(cfg, testRegistry(), slog.New(slog.NewTextHandler(io.Discard, nil)), runDir)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- d.Run(ctx) }()

	sock := filepath.Join(runDir, "loop.sock")
	// wait for the socket to appear
	deadline := time.Now().Add(2 * time.Second)
	for {
		if _, err := os.Stat(sock); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("socket never appeared")
		}
		time.Sleep(10 * time.Millisecond)
	}

	conn, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := conn.Write([]byte("yo")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 2)
	_ = conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(conn, buf); err != nil {
		t.Fatalf("echo through daemon: %v", err)
	}
	if string(buf) != "yo" {
		t.Fatalf("got %q, want yo", buf)
	}
	conn.Close()

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Run returned error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
	if _, err := os.Stat(sock); !os.IsNotExist(err) {
		t.Fatalf("socket not cleaned up: stat err = %v", err)
	}
}

func TestDaemonUnknownTypeFails(t *testing.T) {
	runDir := shortRunDir(t)
	cfg := &config.Config{Devices: []config.Device{
		{Name: "x", Type: "nonesuch", Socket: "x.sock"},
	}}
	d := New(cfg, testRegistry(), slog.New(slog.NewTextHandler(io.Discard, nil)), runDir)
	if err := d.Run(context.Background()); err == nil {
		t.Fatal("expected Run to fail on unknown device type")
	}
}
