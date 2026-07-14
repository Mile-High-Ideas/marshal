// Package mock provides an in-memory echo device for loopback testing the spine.
package mock

import (
	"context"
	"io"
	"sync"
	"time"

	"github.com/Mile-High-Ideas/marshal/internal/bridge"
	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
)

const readTick = 50 * time.Millisecond

// New constructs a mock plugin.
func New(cfg config.Device) (plugin.Plugin, error) {
	return &mockPlugin{}, nil
}

type mockPlugin struct {
	dev *echoDevice
}

func (m *mockPlugin) Open(context.Context) error {
	m.dev = newEchoDevice()
	return nil
}
func (m *mockPlugin) Presentation() plugin.Presentation { return plugin.COMByteStream }
func (m *mockPlugin) Pump(ctx context.Context, guest io.ReadWriteCloser) error {
	return bridge.Pump(ctx, guest, m.dev)
}
func (m *mockPlugin) Close() error {
	if m.dev != nil {
		return m.dev.Close()
	}
	return nil
}

// echoDevice is a loopback: bytes Written are returned by Read. Read returns
// (0,nil) after readTick when idle, honoring the device read-timeout contract.
type echoDevice struct {
	ch     chan []byte
	rem    []byte
	closed chan struct{}
	once   sync.Once
}

func newEchoDevice() *echoDevice {
	return &echoDevice{ch: make(chan []byte, 64), closed: make(chan struct{})}
}
func (d *echoDevice) Write(p []byte) (int, error) {
	cp := append([]byte(nil), p...)
	select {
	case <-d.closed:
		return 0, io.ErrClosedPipe
	case d.ch <- cp:
		return len(p), nil
	}
}
func (d *echoDevice) Read(p []byte) (int, error) {
	if len(d.rem) > 0 {
		n := copy(p, d.rem)
		d.rem = d.rem[n:]
		return n, nil
	}
	select {
	case <-d.closed:
		return 0, io.EOF
	case b := <-d.ch:
		n := copy(p, b)
		if n < len(b) {
			d.rem = append([]byte(nil), b[n:]...)
		}
		return n, nil
	case <-time.After(readTick):
		return 0, nil
	}
}
func (d *echoDevice) Close() error {
	d.once.Do(func() { close(d.closed) })
	return nil
}
