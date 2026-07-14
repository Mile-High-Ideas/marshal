// Package plugin defines the device-plugin contract and a type registry.
package plugin

import (
	"context"
	"fmt"
	"io"

	"github.com/Mile-High-Ideas/marshal/internal/config"
)

// Presentation is how a plugin exposes its device to the guest transport.
type Presentation int

const (
	// COMByteStream is a serial/USB byte stream over a Unix stream socket.
	COMByteStream Presentation = iota
	// RawFrameEndpoint is a raw layer-2 frame endpoint (future: Life Racing).
	RawFrameEndpoint
)

// Plugin owns one physical device. Open/Close bracket the device lifetime
// (claimed once at daemon start). Pump is called once per guest connection and
// returns when that connection ends; the device stays open across reconnects.
type Plugin interface {
	Open(ctx context.Context) error
	Presentation() Presentation
	Pump(ctx context.Context, guest io.ReadWriteCloser) error
	Close() error
}

// Constructor builds a plugin from its device config.
type Constructor func(cfg config.Device) (Plugin, error)

// Registry maps a config `type` string to a constructor.
type Registry struct {
	ctors map[string]Constructor
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{ctors: map[string]Constructor{}}
}

// Register associates a device type with a constructor. A repeated type
// overwrites the previous registration.
func (r *Registry) Register(typ string, c Constructor) {
	r.ctors[typ] = c
}

// Build constructs the plugin for a device, erroring on an unknown type.
func (r *Registry) Build(cfg config.Device) (Plugin, error) {
	c, ok := r.ctors[cfg.Type]
	if !ok {
		return nil, fmt.Errorf("plugin: unknown device type %q", cfg.Type)
	}
	return c(cfg)
}
