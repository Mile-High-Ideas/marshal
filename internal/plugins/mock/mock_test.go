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

func TestEchoDeviceIdleReadTicks(t *testing.T) {
	d := newEchoDevice()
	defer d.Close()

	start := time.Now()
	n, err := d.Read(make([]byte, 8))
	elapsed := time.Since(start)

	if n != 0 {
		t.Errorf("got n=%d, want 0", n)
	}
	if err != nil {
		t.Errorf("got err=%v, want nil", err)
	}

	// Should take approximately readTick (50ms), but allow generous bounds
	// to avoid flakiness: at least half the tick, less than 1 second.
	if elapsed < readTick/2 {
		t.Errorf("elapsed %v too short, want >= %v", elapsed, readTick/2)
	}
	if elapsed >= time.Second {
		t.Errorf("elapsed %v too long, want < 1s", elapsed)
	}
}

func TestPumpReturnsOnContextCancel(t *testing.T) {
	p, err := New(config.Device{Name: "loop", Type: "mock"})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Open(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer p.Close()

	guest, test := net.Pipe()
	defer test.Close()

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)

	go func() {
		done <- p.Pump(ctx, guest)
	}()

	// Cancel without sending any data; Pump should return via tick.
	cancel()

	select {
	case err := <-done:
		if err != context.Canceled {
			t.Logf("Pump returned with error: %v (expected context.Canceled or nil)", err)
		}
	case <-time.After(time.Second):
		t.Fatal("Pump did not return within 1 second after context cancel")
	}
}
