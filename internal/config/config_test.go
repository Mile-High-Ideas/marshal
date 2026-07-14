package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeTemp(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "c.toml")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadValid(t *testing.T) {
	p := writeTemp(t, `
[[device]]
name   = "ecumaster"
type   = "serial"
socket = "ecumaster.sock"
  [device.serial]
  port = "/dev/cu.usbserial-1"
  baud = 115200

[[device]]
name   = "loopback"
type   = "mock"
socket = "loopback.sock"
`)
	cfg, err := Load(p)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(cfg.Devices) != 2 {
		t.Fatalf("want 2 devices, got %d", len(cfg.Devices))
	}
	if cfg.Devices[0].Serial == nil || cfg.Devices[0].Serial.Baud != 115200 {
		t.Fatalf("serial not parsed: %+v", cfg.Devices[0])
	}
}

func TestValidateErrors(t *testing.T) {
	cases := map[string]string{
		"empty name": `
[[device]]
name = ""
type = "mock"
socket = "a.sock"`,
		"empty socket": `
[[device]]
name = "a"
type = "mock"
socket = ""`,
		"dup name": `
[[device]]
name = "a"
type = "mock"
socket = "a.sock"
[[device]]
name = "a"
type = "mock"
socket = "b.sock"`,
		"dup socket": `
[[device]]
name = "a"
type = "mock"
socket = "x.sock"
[[device]]
name = "b"
type = "mock"
socket = "x.sock"`,
		"serial without port": `
[[device]]
name = "a"
type = "serial"
socket = "a.sock"`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			p := writeTemp(t, body)
			if _, err := Load(p); err == nil {
				t.Fatalf("expected error for %q, got nil", name)
			}
		})
	}
}
