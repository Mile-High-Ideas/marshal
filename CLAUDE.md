# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

marshal bridges device I/O across the Parallels boundary so Windows motorsport tuning apps (AiM RaceStudio 3, Life Racing LifeCal, ECUMaster PMU Client) running on an Apple-Silicon Mac can reach real hardware — Windows-on-ARM can't load the vendors' x64 kernel drivers, so device I/O is relocated to macOS userspace.

Authoritative design: @docs/superpowers/specs/2026-07-13-marshal-design.md

## marshald (the Go daemon) — slice 1 built

The core daemon exists: config → plugin registry → device plugins → `bridge.Pump` → one Unix socket per device → daemon lifecycle → `cmd/marshald`. Three plugins ship: `mock` (in-memory echo), `serial` (`/dev/cu.*` via `go.bug.st/serial`), and `aim` (AiM SW4 USB transfer relay). The **Life Racing (raw-L2) plugin is not written yet**; the **AiM SW4** plugin's device side (a libusb control/bulk relay) is built and replay-tested, but its guest-presentation forwarder is a separate open piece — see the design spec and `docs/protocols/aim-sw4-usb.md`.

- Build/run/test go through the **root `Makefile`**: `make build`, `make test`, `make run CONFIG=...`, `make fmt`, `make vet`.
- Test with the race detector: `go test ./... -race`. Every commit must be `gofmt`-clean and `go vet`-clean.
- The `go.mod` `go` directive is **1.25** (a dependency requires it), not 1.23.
- **The `aim` plugin's real libusb device is behind a `//go:build aim_usb` tag** (needs `gousb` → libusb + `pkg-config`). The default build, the full test suite, and the AiM replay test need none of that — only claiming real hardware requires `go build -tags aim_usb`.
- Runtime deps: `go.bug.st/serial` + `github.com/BurntSushi/toml` (and `github.com/google/gousb`, used only under the `aim_usb` tag); test-only `github.com/creack/pty` + `golang.org/x/term`. Keep it lean — stdlib otherwise.

### Non-obvious invariants a new device plugin must respect
- **Device read-timeout tick:** a plugin's device `Read` must return `(0, nil)` on a short idle timeout (`readTick` = 50ms; serial uses `SetReadTimeout`, the mock a channel). This is what lets `bridge.Pump`'s device→guest loop observe context cancellation without the device being closed. A device whose `Read` blocks forever will hang daemon shutdown.
- **`bridge.Pump` closes `guest`, never `device`.** The device is claimed once by `Open` and lives across guest reconnects; only `daemon` closes it, at teardown.
- **One guest per device** — the transport bridges a single guest connection at a time and refuses a second (a COM port is 1:1).
- Plugin registration lives in `cmd/marshald/main.go` (not `internal/plugin`) to avoid an import cycle.

## Discovery & capture kits (`tools/`)

These are the hardware-side kits, separate from the daemon. macOS kits run on the host; Windows kits run inside the Parallels guest or on Shane's standalone x64 PC.

- `tools/usb-discovery/` — macOS. `make help` lists targets; `scan.sh` holds the logic.
- `tools/ecumaster-check/`, `tools/aim-capture/`, `tools/aim-usbcap/` — Windows (`.bat` launcher + `.ps1`).

## Hard constraints

- **Windows PowerShell scripts (`tools/**/*.ps1`) must stay plain ASCII** (or UTF-8 with BOM) — Windows PowerShell 5.1 misparses em-dashes/smart quotes. `.bat`/`.cmd` files must use **CRLF** line endings.
- `tools/usb-discovery/scan.sh` uses **only built-in macOS tools** (`system_profiler`, `ioreg`, …). No Homebrew, `jq`, or Python.
- A committed pre-commit hook (`.githooks/pre-commit`, wired via `core.hooksPath` in `.envrc` — run `direnv allow` once) shellchecks staged shell scripts and validates `.ps1`/`.bat` encoding + line endings. Don't bypass it.

## Device status (see spec for detail)

- **ECUMaster PMU16** — confirmed USB-CDC (VID 0x0483/PID 0x5740) → inbox ARM64 COM port in the guest. **Zero bridge; no `marshald` plugin needed.**
- **AiM SW4** — protocol decoded from USBPcap: vendor control (`bmRequestType 0x42`, `bRequest 1/2`) + bulk OUT `0x01` / bulk IN `0x82`, ASCII/XML payload. **No HID reports** → libusb-ownable on macOS. The `internal/plugins/aim` transfer relay is built and validated against the captured fixture (hardware-free); the **guest-presentation forwarder** (how RS3-in-guest reaches the socket) remains the open piece.
- **Life Racing** — designed (raw layer-2 via BPF); the app↔Protocol-Server IPC redirectability is the open unknown.

## Git

Commits use the `milehighideas` GitHub identity (set by `.envrc` via direnv), never a personal account. Conventional Commits.
