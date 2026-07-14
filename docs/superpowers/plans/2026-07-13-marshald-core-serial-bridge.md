# marshald Core + Serial Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `marshald` daemon core plus a complete serial bridge spine — `guest ↔ Unix socket ↔ Plugin.Pump ↔ device` — loopback-testable on the dev Mac with no vendor hardware.

**Architecture:** A daemon loads a TOML config, builds one `Plugin` per device via a registry, `Open`s each device once, and runs one Unix-socket transport per device. When a guest connects, the transport calls `Plugin.Pump`, which uses a shared `bridge.Pump` to copy bytes bidirectionally between the guest connection and the device. Two plugins ship: `mock` (in-memory echo) and `serial` (`/dev/cu.*` via `go.bug.st/serial`).

**Tech Stack:** Go 1.23+, `go.bug.st/serial` (serial I/O), `github.com/BurntSushi/toml` (config), `github.com/creack/pty` (test-only), stdlib otherwise.

## Global Constraints

- **Module path:** `github.com/Mile-High-Ideas/marshal` — `go.mod` at repo root.
- **Go version floor:** `go 1.23`.
- **Dependencies (runtime):** only `go.bug.st/serial` and `github.com/BurntSushi/toml`. **Test-only:** `github.com/creack/pty`. Everything else stdlib (`net`, `io`, `context`, `log/slog`, `os/signal`, `sync`, `sync/atomic`).
- **Concurrency:** goroutines + `context` + stdlib `sync`. No `errgroup` dependency.
- **Host endpoint:** one Unix domain socket per device. No TCP/PTY host endpoints.
- **Device read contract:** a device's `Read` MUST return `(0, nil)` on a short timeout (default `readTick = 50ms`) so a cancellable copy loop can re-check `ctx`. Serial uses `SetReadTimeout`; the mock uses a timeout-based channel.
- **`bridge.Pump` ownership:** closes `guest` when it returns; NEVER closes `device` (the device lives across guest reconnects).
- **Commits:** Conventional Commits. Author identity resolves to the `milehighideas` account (already configured); do not change it.
- **Formatting:** every commit must be `gofmt`-clean.

---

### Task 1: Module bootstrap + Makefile + skeleton entrypoint

**Files:**
- Create: `go.mod`
- Create: `Makefile`
- Create: `cmd/marshald/main.go`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable module; `marshald` binary that prints a version line and exits.

- [ ] **Step 1: Create `go.mod`**

```text
module github.com/Mile-High-Ideas/marshal

go 1.23
```

- [ ] **Step 2: Create skeleton `cmd/marshald/main.go`**

```go
package main

import (
	"fmt"
	"os"
)

const version = "marshald 0.0.0-dev"

func main() {
	fmt.Fprintln(os.Stdout, version)
}
```

- [ ] **Step 3: Create `Makefile`**

```make
# marshald — build / run / test
SHELL := /bin/bash
CONFIG ?= marshald.toml

.DEFAULT_GOAL := build
.PHONY: build run test fmt vet

build: ## Build all packages
	go build ./...

run: ## Run the daemon: make run CONFIG=path/to.toml
	go run ./cmd/marshald -config $(CONFIG)

test: ## Run all tests
	go test ./...

fmt: ## Format
	gofmt -w .

vet: ## Vet
	go vet ./...
```

- [ ] **Step 4: Verify it builds and runs**

Run: `go build ./... && go run ./cmd/marshald`
Expected: prints `marshald 0.0.0-dev`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add go.mod Makefile cmd/marshald/main.go
git commit -m "feat(marshald): module bootstrap, Makefile, skeleton entrypoint"
```

---

### Task 2: `config` package — TOML parse + validation

**Files:**
- Create: `internal/config/config.go`
- Test: `internal/config/config_test.go`

**Interfaces:**
- Consumes: `github.com/BurntSushi/toml`.
- Produces:
  - `type Config struct { Devices []Device }`
  - `type Device struct { Name, Type, Socket string; Serial *SerialConfig }`
  - `type SerialConfig struct { Port string; Baud int }`
  - `func Load(path string) (*Config, error)`
  - `func (c *Config) Validate() error`

- [ ] **Step 1: Add the dependency**

Run: `go get github.com/BurntSushi/toml@latest`
Expected: adds `github.com/BurntSushi/toml` to `go.mod`.

- [ ] **Step 2: Write the failing tests**

`internal/config/config_test.go`:
```go
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `go test ./internal/config/ -v`
Expected: FAIL — `Load` / `Config` undefined.

- [ ] **Step 4: Write `internal/config/config.go`**

```go
// Package config loads and validates the marshald TOML configuration.
package config

import (
	"fmt"

	"github.com/BurntSushi/toml"
)

// Config is the top-level daemon configuration.
type Config struct {
	Devices []Device `toml:"device"`
}

// Device describes one bridged device.
type Device struct {
	Name   string        `toml:"name"`
	Type   string        `toml:"type"`
	Socket string        `toml:"socket"`
	Serial *SerialConfig `toml:"serial"`
}

// SerialConfig holds serial-plugin parameters.
type SerialConfig struct {
	Port string `toml:"port"`
	Baud int    `toml:"baud"`
}

// Load reads and validates a TOML config file.
func Load(path string) (*Config, error) {
	var c Config
	if _, err := toml.DecodeFile(path, &c); err != nil {
		return nil, fmt.Errorf("config: decode %s: %w", path, err)
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

// Validate enforces structural rules. Unknown device types are enforced later
// by the plugin registry at daemon startup, not here.
func (c *Config) Validate() error {
	if len(c.Devices) == 0 {
		return fmt.Errorf("config: no devices defined")
	}
	names := map[string]bool{}
	sockets := map[string]bool{}
	for i, d := range c.Devices {
		if d.Name == "" {
			return fmt.Errorf("config: device #%d: empty name", i)
		}
		if d.Socket == "" {
			return fmt.Errorf("config: device %q: empty socket", d.Name)
		}
		if names[d.Name] {
			return fmt.Errorf("config: duplicate device name %q", d.Name)
		}
		if sockets[d.Socket] {
			return fmt.Errorf("config: duplicate socket %q", d.Socket)
		}
		names[d.Name] = true
		sockets[d.Socket] = true
		if d.Type == "serial" && (d.Serial == nil || d.Serial.Port == "") {
			return fmt.Errorf("config: device %q: serial requires a port", d.Name)
		}
	}
	return nil
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `go test ./internal/config/ -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/config/
git commit -m "feat(config): TOML load and validation"
```

---

### Task 3: `plugin` package — interface, Presentation, registry

**Files:**
- Create: `internal/plugin/plugin.go`
- Test: `internal/plugin/plugin_test.go`

**Interfaces:**
- Consumes: `internal/config` (`config.Device`).
- Produces:
  - `type Presentation int` with `COMByteStream`, `RawFrameEndpoint`
  - `type Plugin interface { Open(context.Context) error; Presentation() Presentation; Pump(context.Context, io.ReadWriteCloser) error; Close() error }`
  - `type Constructor func(config.Device) (Plugin, error)`
  - `type Registry`; `func NewRegistry() *Registry`; `func (r *Registry) Register(typ string, c Constructor)`; `func (r *Registry) Build(cfg config.Device) (Plugin, error)`

- [ ] **Step 1: Write the failing tests**

`internal/plugin/plugin_test.go`:
```go
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/plugin/ -v`
Expected: FAIL — `NewRegistry` / `Plugin` undefined.

- [ ] **Step 3: Write `internal/plugin/plugin.go`**

```go
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/plugin/ -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/plugin/
git commit -m "feat(plugin): Plugin interface, Presentation, and type registry"
```

---

### Task 4: `bridge` package — bidirectional pump

**Files:**
- Create: `internal/bridge/bridge.go`
- Test: `internal/bridge/bridge_test.go`

**Interfaces:**
- Consumes: nothing (of ours).
- Produces: `func Pump(ctx context.Context, guest, device io.ReadWriteCloser) error`.

**Contract:** copies bytes both ways until the guest closes, the device errors, or `ctx` is cancelled. Closes `guest` before returning; never closes `device`. Requires the device's `Read` to return `(0, nil)` on a timeout tick so the device→guest loop can observe cancellation.

- [ ] **Step 1: Write the failing tests**

`internal/bridge/bridge_test.go`:
```go
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/bridge/ -v`
Expected: FAIL — `Pump` undefined.

- [ ] **Step 3: Write `internal/bridge/bridge.go`**

```go
// Package bridge copies bytes bidirectionally between a guest connection and a
// device for the duration of one guest connection.
package bridge

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"sync"
)

// Pump bridges guest<->device until the guest closes, the device errors, or ctx
// is cancelled. It closes guest before returning and never closes device.
//
// The device's Read must return (0, nil) on a timeout tick so the device->guest
// loop can observe cancellation without being closed.
func Pump(ctx context.Context, guest, device io.ReadWriteCloser) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	var wg sync.WaitGroup
	errs := make([]error, 2)

	wg.Add(2)
	go func() { // guest -> device
		defer wg.Done()
		defer cancel()
		errs[0] = copyCtx(ctx, device, guest)
	}()
	go func() { // device -> guest
		defer wg.Done()
		defer cancel()
		errs[1] = copyCtx(ctx, guest, device)
	}()

	<-ctx.Done()
	_ = guest.Close() // unblock any pending guest I/O; device stays open
	wg.Wait()

	for _, e := range errs {
		if !clean(e) {
			return e
		}
	}
	return nil
}

// copyCtx copies src->dst, re-checking ctx between reads. It returns nil on EOF
// or cancellation; a (0,nil) read is a timeout tick that lets ctx be observed.
func copyCtx(ctx context.Context, dst io.Writer, src io.Reader) error {
	buf := make([]byte, 32*1024)
	for {
		if ctx.Err() != nil {
			return nil
		}
		n, rerr := src.Read(buf)
		if n > 0 {
			if _, werr := dst.Write(buf[:n]); werr != nil {
				return werr
			}
		}
		if rerr != nil {
			if errors.Is(rerr, io.EOF) {
				return nil
			}
			return rerr
		}
	}
}

// clean reports whether err is a normal teardown signal (not a real failure),
// including the errors caused by our own guest.Close().
func clean(err error) bool {
	return err == nil ||
		errors.Is(err, io.EOF) ||
		errors.Is(err, net.ErrClosed) ||
		errors.Is(err, os.ErrClosed) ||
		errors.Is(err, io.ErrClosedPipe)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/bridge/ -race -v`
Expected: PASS (all three tests, no race).

- [ ] **Step 5: Commit**

```bash
git add internal/bridge/
git commit -m "feat(bridge): cancellable bidirectional pump"
```

---

### Task 5: `mock` plugin — in-memory echo device

**Files:**
- Create: `internal/plugins/mock/mock.go`
- Test: `internal/plugins/mock/mock_test.go`

**Interfaces:**
- Consumes: `internal/config`, `internal/plugin`, `internal/bridge`.
- Produces: `func New(cfg config.Device) (plugin.Plugin, error)` registered under type `"mock"`.

- [ ] **Step 1: Write the failing test**

`internal/plugins/mock/mock_test.go`:
```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/plugins/mock/ -v`
Expected: FAIL — `New` undefined.

- [ ] **Step 3: Write `internal/plugins/mock/mock.go`**

```go
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/plugins/mock/ -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/plugins/mock/
git commit -m "feat(plugins/mock): in-memory echo device plugin"
```

---

### Task 6: `serial` plugin — /dev/cu.* via go.bug.st/serial, PTY-tested

**Files:**
- Create: `internal/plugins/serial/serial.go`
- Test: `internal/plugins/serial/serial_test.go`

**Interfaces:**
- Consumes: `internal/config`, `internal/plugin`, `internal/bridge`, `go.bug.st/serial`, `github.com/creack/pty` (test).
- Produces: `func New(cfg config.Device) (plugin.Plugin, error)` registered under type `"serial"`.

**Design note:** device-open sits behind a `open func() (io.ReadWriteCloser, error)` seam so the test injects a PTY-backed device (deadline-wrapped to honor the read-timeout contract) instead of a real serial port.

- [ ] **Step 1: Add dependencies**

Run: `go get go.bug.st/serial@latest github.com/creack/pty@latest`
Expected: adds `go.bug.st/serial` and `github.com/creack/pty` to `go.mod`.

- [ ] **Step 2: Write the failing test**

`internal/plugins/serial/serial_test.go`:
```go
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
	if _, err := test.Write([]byte("AT\r")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	_ = ptmx.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(ptmx, buf); err != nil {
		t.Fatalf("device did not receive guest bytes: %v", err)
	}
	if string(buf) != "AT\r" {
		t.Fatalf("device got %q, want AT\\r", buf)
	}

	// device -> guest: bytes from the physical end should reach the guest
	if _, err := ptmx.Write([]byte("OK\r")); err != nil {
		t.Fatal(err)
	}
	out := make([]byte, 3)
	_ = test.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(test, out); err != nil {
		t.Fatalf("guest did not receive device bytes: %v", err)
	}
	if string(out) != "OK\r" {
		t.Fatalf("guest got %q, want OK\\r", out)
	}
	_ = test.Close()
}

func TestSerialRequiresPort(t *testing.T) {
	if _, err := New(config.Device{Name: "s", Type: "serial"}); err == nil {
		t.Fatal("expected error when serial config/port missing")
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `go test ./internal/plugins/serial/ -v`
Expected: FAIL — `New` / `serialPlugin` undefined.

- [ ] **Step 4: Write `internal/plugins/serial/serial.go`**

```go
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `go test ./internal/plugins/serial/ -race -v`
Expected: PASS (or SKIP if pty unavailable — never FAIL).

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/plugins/serial/
git commit -m "feat(plugins/serial): serial-tty bridge plugin with PTY test"
```

---

### Task 7: `transport` package — Unix socket listener, one guest at a time

**Files:**
- Create: `internal/transport/transport.go`
- Test: `internal/transport/transport_test.go`

**Interfaces:**
- Consumes: `internal/plugin`, `internal/plugins/mock` (test), `log/slog`.
- Produces:
  - `func New(name, socket string, p plugin.Plugin, log *slog.Logger) *Transport`
  - `func (t *Transport) Name() string`
  - `func (t *Transport) Start() error` — remove stale socket, bind listener
  - `func (t *Transport) Serve(ctx context.Context) error` — accept loop; one active guest, refuse extras
  - `func (t *Transport) Close() error` — close listener, unlink socket

**Test socket paths:** use a short dir under `/tmp` (e.g. `os.MkdirTemp("/tmp", "md")`), NOT `t.TempDir()` — macOS Unix socket paths are capped near 104 bytes and `t.TempDir()` is long.

- [ ] **Step 1: Write the failing tests**

`internal/transport/transport_test.go`:
```go
package transport

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
	"github.com/Mile-High-Ideas/marshal/internal/plugins/mock"
)

func shortSocket(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "md")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return filepath.Join(dir, "d.sock")
}

func startTransport(t *testing.T) (*Transport, string, context.CancelFunc) {
	t.Helper()
	sock := shortSocket(t)
	p, err := mock.New(config.Device{Name: "loop", Type: "mock"})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Open(context.Background()); err != nil {
		t.Fatal(err)
	}
	tr := New("loop", sock, p, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := tr.Start(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	go tr.Serve(ctx)
	return tr, sock, cancel
}

func TestTransportEchoes(t *testing.T) {
	tr, sock, cancel := startTransport(t)
	defer cancel()
	defer tr.Close()

	conn, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte("hey")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	_ = conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(conn, buf); err != nil {
		t.Fatalf("echo: %v", err)
	}
	if string(buf) != "hey" {
		t.Fatalf("got %q, want hey", buf)
	}
}

func TestTransportRefusesSecondGuest(t *testing.T) {
	tr, sock, cancel := startTransport(t)
	defer cancel()
	defer tr.Close()

	c1, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c1.Close()
	// ensure c1 is the active guest
	if _, err := c1.Write([]byte("x")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 1)
	_ = c1.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := io.ReadFull(c1, buf); err != nil {
		t.Fatalf("first guest echo: %v", err)
	}

	// second guest should be refused: the connection is closed by the server
	c2, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	_ = c2.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := c2.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("second guest: want EOF (refused), got %v", err)
	}
}
```

The test uses `mock.New` directly — it returns `plugin.Plugin`, which `transport.New` accepts.

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/transport/ -v`
Expected: FAIL — `New` / `Transport` undefined.

- [ ] **Step 3: Write `internal/transport/transport.go`**

```go
// Package transport exposes one Unix-domain-socket endpoint per device and
// bridges a single guest connection at a time to the device plugin.
package transport

import (
	"context"
	"log/slog"
	"net"
	"os"
	"sync/atomic"

	"github.com/Mile-High-Ideas/marshal/internal/plugin"
)

// Transport is one device's Unix-socket endpoint.
type Transport struct {
	name   string
	socket string
	plug   plugin.Plugin
	log    *slog.Logger
	ln     net.Listener
	busy   atomic.Bool
}

// New builds a transport for a device. Call Start, then Serve.
func New(name, socket string, p plugin.Plugin, log *slog.Logger) *Transport {
	return &Transport{name: name, socket: socket, plug: p, log: log}
}

// Name returns the device name.
func (t *Transport) Name() string { return t.name }

// Start removes any stale socket and binds the listener.
func (t *Transport) Start() error {
	_ = os.Remove(t.socket)
	ln, err := net.Listen("unix", t.socket)
	if err != nil {
		return err
	}
	t.ln = ln
	return nil
}

// Serve accepts guest connections. Exactly one guest is bridged at a time; a
// second concurrent connection is refused (closed). Returns nil when the
// listener is closed after ctx is done.
func (t *Transport) Serve(ctx context.Context) error {
	for {
		conn, err := t.ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		if !t.busy.CompareAndSwap(false, true) {
			t.log.Warn("refusing second concurrent guest", "device", t.name)
			_ = conn.Close()
			continue
		}
		go t.handle(ctx, conn)
	}
}

func (t *Transport) handle(ctx context.Context, conn net.Conn) {
	defer t.busy.Store(false)
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// bridge.Pump (inside plug.Pump) closes conn on return.
	if err := t.plug.Pump(cctx, conn); err != nil {
		t.log.Error("pump ended with error", "device", t.name, "err", err)
		return
	}
	t.log.Info("guest disconnected", "device", t.name)
}

// Close stops accepting and removes the socket file.
func (t *Transport) Close() error {
	var err error
	if t.ln != nil {
		err = t.ln.Close()
	}
	_ = os.Remove(t.socket)
	return err
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/transport/ -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/transport/
git commit -m "feat(transport): unix-socket endpoint, one guest at a time"
```

---

### Task 8: `daemon` package — wiring, lifecycle, shutdown

**Files:**
- Create: `internal/daemon/daemon.go`
- Test: `internal/daemon/daemon_test.go`

**Interfaces:**
- Consumes: `internal/config`, `internal/plugin`, `internal/transport`, `internal/plugins/mock` (test), `log/slog`.
- Produces:
  - `func New(cfg *config.Config, reg *plugin.Registry, log *slog.Logger, runDir string) *Daemon`
  - `func (d *Daemon) Run(ctx context.Context) error` — mkdir runDir, build+open all plugins, start+serve transports, block on ctx, then shut down and unlink sockets.

- [ ] **Step 1: Write the failing tests**

`internal/daemon/daemon_test.go`:
```go
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/daemon/ -v`
Expected: FAIL — `New` / `Daemon` undefined.

- [ ] **Step 3: Write `internal/daemon/daemon.go`**

```go
// Package daemon wires config + plugins + transports into a runnable daemon.
package daemon

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
	"github.com/Mile-High-Ideas/marshal/internal/transport"
)

// Daemon owns the devices and their transports for one process lifetime.
type Daemon struct {
	cfg    *config.Config
	reg    *plugin.Registry
	log    *slog.Logger
	runDir string
}

// New builds a daemon. runDir is where per-device sockets are created.
func New(cfg *config.Config, reg *plugin.Registry, log *slog.Logger, runDir string) *Daemon {
	return &Daemon{cfg: cfg, reg: reg, log: log, runDir: runDir}
}

// Run builds and opens every device, serves each on its socket, blocks until
// ctx is cancelled, then shuts down cleanly. Any startup failure aborts with a
// clean partial teardown.
func (d *Daemon) Run(ctx context.Context) error {
	if err := os.MkdirAll(d.runDir, 0o700); err != nil {
		return fmt.Errorf("daemon: runtime dir: %w", err)
	}

	var opened []plugin.Plugin
	var transports []*transport.Transport
	teardown := func() {
		for _, t := range transports {
			_ = t.Close()
		}
		for i := len(opened) - 1; i >= 0; i-- {
			_ = opened[i].Close()
		}
	}

	for _, dev := range d.cfg.Devices {
		p, err := d.reg.Build(dev)
		if err != nil {
			teardown()
			return fmt.Errorf("daemon: device %q: %w", dev.Name, err)
		}
		if err := p.Open(ctx); err != nil {
			teardown()
			return fmt.Errorf("daemon: open %q: %w", dev.Name, err)
		}
		opened = append(opened, p)

		sock := filepath.Join(d.runDir, dev.Socket)
		tr := transport.New(dev.Name, sock, p, d.log)
		if err := tr.Start(); err != nil {
			teardown()
			return fmt.Errorf("daemon: listen %q: %w", dev.Name, err)
		}
		transports = append(transports, tr)
	}

	var wg sync.WaitGroup
	for _, tr := range transports {
		tr := tr
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := tr.Serve(ctx); err != nil {
				d.log.Error("serve stopped", "device", tr.Name(), "err", err)
			}
		}()
	}
	d.log.Info("marshald running", "devices", len(transports), "runDir", d.runDir)

	<-ctx.Done()
	d.log.Info("shutting down")
	teardown()
	wg.Wait()
	return nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/daemon/ -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/daemon/
git commit -m "feat(daemon): wiring, lifecycle, and clean shutdown"
```

---

### Task 9: `cmd/marshald` entrypoint — CLI wiring

**Files:**
- Modify: `cmd/marshald/main.go` (replace the skeleton)
- Create: `marshald.example.toml`

**Interfaces:**
- Consumes: `internal/config`, `internal/plugin`, `internal/daemon`, `internal/plugins/mock`, `internal/plugins/serial`.
- Produces: a `marshald -config <path>` binary that registers the `mock` and `serial` plugins and runs the daemon until SIGINT/SIGTERM.

**Note:** plugin registration lives here (not in `internal/plugin`) to avoid an import cycle (`plugin` ← `plugins/*` ← `plugin`).

- [ ] **Step 1: Replace `cmd/marshald/main.go`**

```go
// Command marshald bridges macOS-side devices to Parallels guest apps.
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/daemon"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/mock"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/serial"
)

func main() {
	configPath := flag.String("config", "", "path to the TOML config file")
	flag.Parse()

	log := slog.New(slog.NewTextHandler(os.Stderr, nil))

	if *configPath == "" {
		log.Error("missing required -config flag")
		os.Exit(2)
	}
	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Error("load config", "err", err)
		os.Exit(1)
	}

	reg := plugin.NewRegistry()
	reg.Register("mock", mock.New)
	reg.Register("serial", serial.New)

	home, err := os.UserHomeDir()
	if err != nil {
		log.Error("resolve home dir", "err", err)
		os.Exit(1)
	}
	runDir := filepath.Join(home, ".marshald", "run")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	d := daemon.New(cfg, reg, log, runDir)
	if err := d.Run(ctx); err != nil {
		log.Error("daemon exited", "err", err)
		os.Exit(1)
	}
}
```

- [ ] **Step 2: Create `marshald.example.toml`**

```toml
# Example marshald config. Socket paths are relative to ~/.marshald/run/.

[[device]]
name   = "ecumaster"
type   = "serial"
socket = "ecumaster.sock"
  [device.serial]
  port = "/dev/cu.usbserial-XXXX"   # find with: ls /dev/cu.*
  baud = 115200

[[device]]
name   = "loopback"
type   = "mock"
socket = "loopback.sock"
```

- [ ] **Step 3: Verify build + a live smoke test**

Run:
```bash
go build ./...
go run ./cmd/marshald -config marshald.example.toml &
sleep 1
printf 'ping' | nc -U ~/.marshald/run/loopback.sock -w1
kill %1
```
Expected: the `nc` command prints `ping` (the mock echoes it); daemon logs "marshald running" then "shutting down"; no leftover `~/.marshald/run/*.sock`.

- [ ] **Step 4: Verify the full suite is green and formatted**

Run: `gofmt -l . && go vet ./... && go test ./... -race`
Expected: `gofmt -l` prints nothing; vet clean; all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add cmd/marshald/main.go marshald.example.toml
git commit -m "feat(marshald): CLI entrypoint wiring mock and serial plugins"
```

---

## Self-Review

**Spec coverage:**
- Core lifecycle (config → build/open → transport → shutdown) → Tasks 8, 9. ✓
- `Plugin` interface + registry → Task 3. ✓
- Unix socket per device → Task 7. ✓
- Shared `bridge.Pump` → Task 4. ✓
- `mock` + `serial` plugins → Tasks 5, 6. ✓
- TOML config (`BurntSushi/toml`) → Task 2. ✓
- Loopback test (mock) → Tasks 5, 7, 8. ✓
- PTY serial test → Task 6. ✓
- Config validation table tests → Task 2. ✓
- "Device stays open across reconnects" → Task 4 (`Pump` never closes device) + Task 8. ✓
- "Refuse a second concurrent guest" → Task 7. ✓
- Cancellable reads (read-timeout contract) → Tasks 4, 5, 6 (`readTick`). ✓
- Structured `slog` logging → Tasks 7, 8, 9. ✓
- Clean shutdown, no leaked sockets → Tasks 7, 8 (`Close` unlinks), verified Task 8 test + Task 9 smoke. ✓
- Root `Makefile` (`build`/`run`/`test`) → Task 1. ✓
- Definition of done items → covered across Tasks 4–9. ✓

**Out of scope confirmed absent:** no `gousb`/raw USB, no `RawFrameEndpoint` implementation (only the enum constant, reserved), no TCP/PTY host endpoints, no auto-reopen, no CI wiring. ✓

**Type consistency:** `config.Device`/`config.SerialConfig` fields, `plugin.Plugin`/`Constructor`/`Registry.Build`, `bridge.Pump(ctx, guest, device)`, `mock.New`/`serial.New` (both `func(config.Device) (plugin.Plugin, error)`), `transport.New(name, socket, plugin.Plugin, *slog.Logger)` + `Name/Start/Serve/Close`, `daemon.New(cfg, reg, log, runDir)` + `Run(ctx)` — all used consistently across tasks. `readTick = 50ms` defined in `mock` and `serial`; test doubles use their own tick. ✓

**Placeholder scan:** no `TBD`/`TODO`/"handle edge cases"/vague steps; every code step carries complete, compilable code. Clean.
