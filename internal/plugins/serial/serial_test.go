package serial

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"testing"
	"time"

	"github.com/creack/pty"
	"golang.org/x/term"

	"github.com/Mile-High-Ideas/marshal/internal/config"
)

// deadlineDevice wraps a pty end to mimic a serial read timeout: Read returns
// (0,nil) if no byte arrives within readTick.
type deadlineDevice struct{ f *os.File }

func (d deadlineDevice) Read(p []byte) (int, error) {
	_ = d.f.SetReadDeadline(time.Now().Add(readTick))
	n, err := d.f.Read(p)
	if err != nil && errors.Is(err, os.ErrDeadlineExceeded) {
		return n, nil
	}
	return n, err
}
func (d deadlineDevice) Write(p []byte) (int, error) { return d.f.Write(p) }
func (d deadlineDevice) Close() error                { return d.f.Close() }

func TestSerialPumpsOverPTY(t *testing.T) {
	ptmx, tty, err := pty.Open() // ptmx = physical-device end; tty = our device
	if err != nil {
		t.Skipf("pty unavailable: %v", err)
	}
	defer ptmx.Close()

	// Put the pty into raw mode so it's a clean byte pipe: default macOS ptys
	// are canonical/cooked (ICRNL translates \r->\n, line-buffered reads, echo),
	// which corrupts a raw serial-style byte stream.
	if _, err := term.MakeRaw(int(tty.Fd())); err != nil {
		t.Skipf("cannot set pty raw mode: %v", err)
	}

	p, err := New(config.Device{
		Name: "s", Type: "serial",
		Serial: &config.SerialConfig{Port: "unused", Baud: 115200},
	})
	if err != nil {
		t.Fatal(err)
	}
	// inject the pty tty end via the seam instead of opening a real serial port
	p.(*serialPlugin).open = func() (io.ReadWriteCloser, error) {
		return deadlineDevice{f: tty}, nil
	}
	if err := p.Open(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer p.Close()

	guest, test := net.Pipe()
	go p.Pump(context.Background(), guest)

	// guest -> device: bytes should reach the physical (ptmx) end
	if _, err := test.Write([]byte("ATI")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	_ = ptmx.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(ptmx, buf); err != nil {
		t.Fatalf("device did not receive guest bytes: %v", err)
	}
	if string(buf) != "ATI" {
		t.Fatalf("device got %q, want ATI", buf)
	}

	// device -> guest: bytes from the physical end should reach the guest
	if _, err := ptmx.Write([]byte("OKR")); err != nil {
		t.Fatal(err)
	}
	out := make([]byte, 3)
	_ = test.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(test, out); err != nil {
		t.Fatalf("guest did not receive device bytes: %v", err)
	}
	if string(out) != "OKR" {
		t.Fatalf("guest got %q, want OKR", out)
	}
	_ = test.Close()
}

func TestSerialRequiresPort(t *testing.T) {
	if _, err := New(config.Device{Name: "s", Type: "serial"}); err == nil {
		t.Fatal("expected error when serial config/port missing")
	}
}
