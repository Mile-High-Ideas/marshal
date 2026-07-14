package plugin

import (
	"context"
	"errors"
	"io"
	"testing"

	"github.com/Mile-High-Ideas/marshal/internal/config"
)

type stubPlugin struct{ name string }

func (s *stubPlugin) Open(context.Context) error                     { return nil }
func (s *stubPlugin) Presentation() Presentation                     { return COMByteStream }
func (s *stubPlugin) Pump(context.Context, io.ReadWriteCloser) error { return nil }
func (s *stubPlugin) Close() error                                   { return nil }

func TestRegistryBuild(t *testing.T) {
	r := NewRegistry()
	r.Register("stub", func(cfg config.Device) (Plugin, error) {
		return &stubPlugin{name: cfg.Name}, nil
	})

	p, err := r.Build(config.Device{Name: "d1", Type: "stub"})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if sp, ok := p.(*stubPlugin); !ok || sp.name != "d1" {
		t.Fatalf("unexpected plugin: %#v", p)
	}
}

func TestRegistryUnknownType(t *testing.T) {
	r := NewRegistry()
	_, err := r.Build(config.Device{Name: "d1", Type: "nope"})
	if err == nil {
		t.Fatal("expected error for unknown type")
	}
}

func TestRegistryConstructorError(t *testing.T) {
	r := NewRegistry()
	r.Register("bad", func(config.Device) (Plugin, error) {
		return nil, errors.New("boom")
	})
	if _, err := r.Build(config.Device{Name: "d", Type: "bad"}); err == nil {
		t.Fatal("expected constructor error to propagate")
	}
}
