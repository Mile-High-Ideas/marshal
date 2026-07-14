# marshald — core + serial bridge (build-order slice 1)

**Status:** Design approved (2026-07-13)
**Author:** Brandon Shutter (with Claude)
**Language:** Go
**Parent design:** [2026-07-13-marshal-design.md](2026-07-13-marshal-design.md)

---

## 1. Scope

The first implementation slice of `marshald`: the daemon **core** plus the full
**serial bridge spine** — `guest ↔ Unix socket ↔ Plugin.Pump ↔ device` — proven
**loopback-first on the development Mac with no vendor hardware**.

ECUMaster is the reference serial device. Because its cable is confirmed to
enumerate as a standard USB-serial device (macOS exposes it as a `/dev/cu.*`
node), the device side of this slice is a **serial tty**, not raw USB via
`gousb`. Raw USB (`gousb`/libusb) is the AiM path and is out of scope here.

This slice satisfies the parent design's build-order step 1 ("Scaffold marshald
core + vSerial bridge → ECUMaster working, or confirmed zero-bridge") and its
"add a device = write one plugin" reusability criterion.

### In scope
- Daemon lifecycle: config load, plugin build/open, per-device transport, signal-driven shutdown.
- `Plugin` interface + registry.
- One **Unix domain socket per device** as the host endpoint the Parallels
  virtual serial port attaches to.
- Shared bidirectional `bridge.Pump`.
- Two plugins: `mock` (in-memory echo) and `serial` (`/dev/cu.*` via `go.bug.st/serial`).
- Loopback + PTY + unit tests, all runnable on the dev Mac.
- Root `Makefile` with `build` / `run` / `test` targets wrapping the `go` toolchain.

### Out of scope (this slice)
- Raw layer-2 / `RawFrameEndpoint` (Life Racing) and raw USB `gousb` (AiM).
- Auto-reopen/retry of a failed device.
- TCP or PTY host endpoints (Unix socket only).
- Real Parallels/guest end-to-end validation (happens later on the hardware Mac).
- CI wiring for `gofmt`/`go vet` (noted as a follow-up).

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Architecture | Spec-faithful `Plugin` interface + shared `bridge.Pump` helper | Hard non-stream devices (raw-L2, AiM) keep pump control; simple stream plugins stay tiny. |
| Host endpoint | One Unix domain socket per device | Matches Parallels vSerial "socket" mode on macOS; no port management; filesystem-permissioned; not network-exposed. |
| Device side (this slice) | Serial tty via `go.bug.st/serial` | ECUMaster is USB-serial; the OS already gives a `/dev/cu.*` node. |
| Config format | TOML (`github.com/BurntSushi/toml`) | Comment-friendly, idiomatic for daemons. |
| Concurrency | Goroutines + context + stdlib `sync` per parent design | Byte-pumping is the daemon's essence. |
| Logging | stdlib `log/slog` | No dependency; structured. |

## 3. Module & layout

Module `github.com/Mile-High-Ideas/marshal`, `go.mod` at repo root (the daemon is
the repo's primary artifact). `tools/` and `docs/` are unchanged.

```bash
go.mod
Makefile                    # build / run / test targets (wraps `go` commands)
cmd/marshald/main.go        # entrypoint: flags, load config, run daemon
internal/
  config/                   # TOML parse + validation
  plugin/                   # Plugin interface, Presentation, Registry
  bridge/                   # Pump helper (bidirectional copy)
  transport/                # Unix-socket listener per device
  daemon/                   # wiring + lifecycle/signals
  plugins/
    mock/                   # echo/loopback plugin
    serial/                 # serial-tty plugin (go.bug.st/serial)
```

### Dependencies
- `go.bug.st/serial` — serial port I/O (only real runtime dep this slice needs).
- `github.com/BurntSushi/toml` — config parsing.
- `github.com/creack/pty` — **test-only**, fakes a serial device via a PTY pair.
- Otherwise **stdlib only**: `net`, `io`, `context`, `log/slog`, `os/signal`, `sync`.
  Pump coordination uses `sync.WaitGroup` + a shared first-error — no `errgroup` dependency.

## 4. Interfaces & components

### 4.1 `plugin`
```go
type Presentation int
const (
    COMByteStream    Presentation = iota // stream socket ↔ serial/USB byte stream
    RawFrameEndpoint                      // future: Life Racing raw-L2
)

type Plugin interface {
    Open(ctx context.Context) error                            // claim the physical device
    Presentation() Presentation
    Pump(ctx context.Context, guest io.ReadWriteCloser) error  // bridge ONE guest connection
    Close() error
}

type Constructor func(cfg config.Device) (Plugin, error)       // registered per config `type`
```
`Open`/`Close` bracket the **device** lifetime (claimed once at daemon start).
`Pump` is called per **guest** connection and returns when that connection ends;
the device stays open across guest reconnects.

### 4.2 `bridge`
`Pump(ctx context.Context, guest, device io.ReadWriteCloser) error` — the shared
bidirectional copy. Simple stream plugins implement `Plugin.Pump` as
`return bridge.Pump(ctx, guest, b.device)`. Semantics in §6.

### 4.3 `plugins/mock`
In-memory echo device (a `ReadWriteCloser` returning what was written), with an
interruptible pipe so reads honor context. Deterministic test vehicle; no OS resources.

### 4.4 `plugins/serial`
Opens the configured `/dev/cu.*` at the given baud via `go.bug.st/serial`,
exposing it as the device `ReadWriteCloser` with a short `SetReadTimeout` so its
read loop stays cancellable. Device-open sits behind a small seam so tests can
substitute a PTY (or raw fd) instead of a real serial port.

### 4.5 `transport`
One Unix-socket listener per device. Both `serial` and `mock` present as
`COMByteStream` → a stream Unix socket. Accept-loop semantics in §6.

### 4.6 `config` + `daemon`
`config` parses/validates the TOML. `daemon` wires it: load config → build+`Open`
each plugin via the registry → start a transport per device → block until signal
→ clean shutdown.

### 4.7 Config shape
```toml
[[device]]
name   = "ecumaster"
type   = "serial"
socket = "ecumaster.sock"        # relative to the runtime dir (§6)
  [device.serial]
  port = "/dev/cu.usbserial-XXXX"
  baud = 115200

[[device]]
name   = "loopback"
type   = "mock"
socket = "loopback.sock"
```

## 5. Data flow

```text
guest app → COMx → Parallels vSerial → <device>.sock → transport → plugin.Pump → bridge.Pump → serial /dev/cu.* → device
```

## 6. Lifecycle, concurrency & error handling

### Startup
1. `main` loads TOML; builds a root context cancelled by SIGINT/SIGTERM.
2. `daemon` creates the runtime dir (`~/.marshald/run/`, `0700`) and removes stale `.sock` files.
3. Per device: registry builds the plugin → `plugin.Open(ctx)` claims the device.
   Any `Open` failure → clean shutdown, non-zero exit (no half-started daemon).
4. Start one transport listener per device.

### Accept-loop (one guest at a time)
A COM port is 1:1: each transport runs a single guest connection at a time —
`Accept` → `plugin.Pump(ctx, conn)` to completion → loop to `Accept` the next. A
second concurrent connection is closed immediately (refused, not queued);
Parallels opens exactly one.

### `bridge.Pump` semantics
- Two goroutines under a per-connection context, coordinated by a `sync.WaitGroup` and a shared first-error: `guest→device` and `device→guest`.
- **Guest closes** (EOF/error): cancel the connection context and return; the
  **device stays open** for the next guest.
- The `device→guest` goroutine must not block forever on a quiet read after the
  guest is gone: the serial device uses a short `SetReadTimeout`, so its read loop
  wakes periodically and honors cancellation; the mock uses an interruptible pipe.
- **Device error** (unplugged, I/O failure): cancel the context, unwind both
  goroutines, return the error. The accept-loop logs it and resumes waiting for a
  guest. (Auto-reopening a failed device is a follow-up, not this slice.)

### Rationale for the two contested defaults
- *Device stays open across reconnects* — the device is an exclusive claim, and
  vendor apps open/close the COM port repeatedly within a session; re-claiming per
  reconnect adds latency and risks a denied claim mid-session. Matches `socat`/`ser2net`.
- *Refuse a second concurrent guest* — a COM port is single-owner; two writers
  interleaving bytes corrupt the protocol. Refusing surfaces misconfiguration
  instead of hiding it.

Both are cheap to revisit if real hardware disagrees.

### Shutdown (signal)
Cancel root context → close all listeners → close active guest conns (unblocks
`Pump`) → `plugin.Close()` each device → unlink socket files. Structured `slog`
at each transition; device-side errors are logged, never silently swallowed.

## 7. Testing strategy

All runnable on the dev Mac with no vendor hardware:

- **`bridge.Pump` unit tests:** both sides via `net.Pipe()`. Assert bytes flow
  both ways; closing the guest side unwinds cleanly and leaves the device open; a
  device-side error propagates as `Pump`'s return.
- **Mock-plugin loopback test:** `transport` + `mock` on a temp Unix socket;
  `net.Dial`, write, read the echo. Proves the whole spine without an OS device.
- **Serial-plugin PTY test:** `creack/pty` master/slave pair; point the serial
  plugin at the slave; write to the master (playing the device) and assert bytes
  reach the guest socket, and vice versa. If `go.bug.st/serial` rejects a PTY's
  termios on macOS, the device-open seam injects the pty fd directly. Skips (not
  fails) if PTY setup is unavailable.
- **Config table tests:** valid file parses; unknown `type`, missing serial
  `port`, duplicate `name`/`socket` each error at load.
- **Gate:** `make test` → `go test ./...`. `gofmt`/`go vet` in CI is a follow-up.

## 8. Definition of done

- `marshald` builds and runs from a TOML config.
- Mock loopback test passes: a client on the device socket gets its bytes echoed
  through the full transport → plugin → device path.
- Serial PTY test passes: real serial byte-pumping in both directions.
- Config validation rejects the malformed cases above at startup.
- Clean startup/shutdown with structured logs; no leaked socket files.
- `go test ./...` green.
