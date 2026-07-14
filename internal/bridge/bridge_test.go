package bridge

import (
	"context"
	"errors"
	"net"
	"sync"
	"testing"
	"time"
)

const testTick = 20 * time.Millisecond

// fakeDevice satisfies the device read-timeout contract: Read returns bytes
// pushed via emit(), or (0,nil) after testTick when idle. Writes are captured.
type fakeDevice struct {
	toGuest chan []byte
	mu      sync.Mutex
	written []byte
	readErr error
	closed  chan struct{}
	once    sync.Once
}

func newFakeDevice() *fakeDevice {
	return &fakeDevice{toGuest: make(chan []byte, 16), closed: make(chan struct{})}
}
func (d *fakeDevice) emit(b []byte) { d.toGuest <- b }
func (d *fakeDevice) Read(p []byte) (int, error) {
	d.mu.Lock()
	re := d.readErr
	d.mu.Unlock()
	if re != nil {
		return 0, re
	}
	select {
	case <-d.closed:
		return 0, nil // treated as a tick; test uses readErr for real errors
	case b := <-d.toGuest:
		return copy(p, b), nil
	case <-time.After(testTick):
		return 0, nil
	}
}
func (d *fakeDevice) Write(p []byte) (int, error) {
	d.mu.Lock()
	d.written = append(d.written, p...)
	d.mu.Unlock()
	return len(p), nil
}
func (d *fakeDevice) Close() error {
	d.once.Do(func() { close(d.closed) })
	return nil
}
func (d *fakeDevice) isClosed() bool {
	select {
	case <-d.closed:
		return true
	default:
		return false
	}
}
func (d *fakeDevice) captured() []byte {
	d.mu.Lock()
	defer d.mu.Unlock()
	return append([]byte(nil), d.written...)
}

func TestPumpBidirectional(t *testing.T) {
	guest, test := net.Pipe()
	dev := newFakeDevice()
	done := make(chan error, 1)
	go func() { done <- Pump(context.Background(), guest, dev) }()

	// guest -> device
	if _, err := test.Write([]byte("hello")); err != nil {
		t.Fatal(err)
	}
	// device -> guest
	dev.emit([]byte("world"))
	buf := make([]byte, 5)
	_ = test.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := test.Read(buf); err != nil {
		t.Fatalf("read from guest: %v", err)
	}
	if string(buf) != "world" {
		t.Fatalf("guest got %q, want world", buf)
	}
	// let the guest->device copy land
	time.Sleep(50 * time.Millisecond)
	if got := string(dev.captured()); got != "hello" {
		t.Fatalf("device captured %q, want hello", got)
	}
	_ = test.Close()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Pump did not return after guest close")
	}
}

func TestPumpGuestCloseLeavesDeviceOpen(t *testing.T) {
	guest, test := net.Pipe()
	dev := newFakeDevice()
	done := make(chan error, 1)
	go func() { done <- Pump(context.Background(), guest, dev) }()

	_ = test.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Pump returned error on clean guest close: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("Pump did not return")
	}
	if dev.isClosed() {
		t.Fatal("device was closed; it must stay open across reconnects")
	}
}

func TestPumpDeviceErrorPropagates(t *testing.T) {
	guest, _ := net.Pipe()
	dev := newFakeDevice()
	dev.mu.Lock()
	dev.readErr = errors.New("device unplugged")
	dev.mu.Unlock()
	done := make(chan error, 1)
	go func() { done <- Pump(context.Background(), guest, dev) }()

	select {
	case err := <-done:
		if err == nil || err.Error() != "device unplugged" {
			t.Fatalf("want device error, got %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("Pump did not return on device error")
	}
}
