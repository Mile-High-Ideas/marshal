package mock

import (
	"context"
	"net"
	"testing"
	"time"

	"github.com/Mile-High-Ideas/marshal/internal/config"
)

func TestMockEchoesThroughPump(t *testing.T) {
	p, err := New(config.Device{Name: "loop", Type: "mock"})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Open(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer p.Close()

	guest, test := net.Pipe()
	go p.Pump(context.Background(), guest)

	if _, err := test.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 4)
	_ = test.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := test.Read(buf); err != nil {
		t.Fatalf("read echo: %v", err)
	}
	if string(buf) != "ping" {
		t.Fatalf("got %q, want ping", buf)
	}
	_ = test.Close()
}
