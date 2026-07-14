// Package serial bridges a /dev/cu.* serial device (e.g. a USB-CDC/FTDI cable)
// to a guest connection.
package serial

import (
	"context"
	"fmt"
	"io"
	"time"

	goserial "go.bug.st/serial"

	"github.com/Mile-High-Ideas/marshal/internal/bridge"
	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
)

const readTick = 50 * time.Millisecond

const defaultBaud = 115200

// New constructs a serial plugin. It errors if no port is configured.
func New(cfg config.Device) (plugin.Plugin, error) {
	if cfg.Serial == nil || cfg.Serial.Port == "" {
		return nil, fmt.Errorf("serial: device %q requires a port", cfg.Name)
	}
	sc := *cfg.Serial
	if sc.Baud == 0 {
		sc.Baud = defaultBaud
	}
	p := &serialPlugin{cfg: sc}
	p.open = p.openSerial
	return p, nil
}

type serialPlugin struct {
	cfg  config.SerialConfig
	open func() (io.ReadWriteCloser, error) // seam; overridable in tests
	dev  io.ReadWriteCloser
}

func (p *serialPlugin) openSerial() (io.ReadWriteCloser, error) {
	port, err := goserial.Open(p.cfg.Port, &goserial.Mode{BaudRate: p.cfg.Baud})
	if err != nil {
		return nil, fmt.Errorf("serial: open %s: %w", p.cfg.Port, err)
	}
	if err := port.SetReadTimeout(readTick); err != nil {
		_ = port.Close()
		return nil, fmt.Errorf("serial: set read timeout: %w", err)
	}
	return port, nil
}

func (p *serialPlugin) Open(context.Context) error {
	d, err := p.open()
	if err != nil {
		return err
	}
	p.dev = d
	return nil
}
func (p *serialPlugin) Presentation() plugin.Presentation { return plugin.COMByteStream }
func (p *serialPlugin) Pump(ctx context.Context, guest io.ReadWriteCloser) error {
	return bridge.Pump(ctx, guest, p.dev)
}
func (p *serialPlugin) Close() error {
	if p.dev != nil {
		return p.dev.Close()
	}
	return nil
}
