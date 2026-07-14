# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

marshal bridges device I/O across the Parallels boundary so Windows motorsport tuning apps (AiM RaceStudio 3, Life Racing LifeCal, ECUMaster PMU Client) running on an Apple-Silicon Mac can reach real hardware — Windows-on-ARM can't load the vendors' x64 kernel drivers, so device I/O is relocated to macOS userspace.

Authoritative design: @docs/superpowers/specs/2026-07-13-marshal-design.md

## marshald (the Go daemon) — slice 1 built

The core daemon exists: config → plugin registry → device plugins → `bridge.Pump` → one Unix socket per device → daemon lifecycle → `cmd/marshald`. Two plugins ship: `mock` (in-memory echo) and `serial` (`/dev/cu.*` via `go.bug.st/serial`). The **Life Racing (raw-L2) and AiM SW4 (libusb) plugins are not written yet** — see the design spec for their tactics.

- Build/run/test go through the **root `Makefile`**: `make build`, `make test`, `make run CONFIG=...`, `make fmt`, `make vet`.
- Test with the race detector: `go test ./... -race`. Every commit must be `gofmt`-clean and `go vet`-clean.
- The `go.mod` `go` directive is **1.25** (a dependency requires it), not 1.23.
- Runtime deps are limited to `go.bug.st/serial` + `github.com/BurntSushi/toml`; test-only `github.com/creack/pty` + `golang.org/x/term`. Keep it lean — stdlib otherwise.

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
- **AiM SW4** — protocol decoded from USBPcap: vendor control (`bmRequestType 0x42`, `bRequest 1/2`) + bulk OUT `0x01` / bulk IN `0x82`, ASCII/XML payload. **No HID reports** → libusb-ownable on macOS. Open piece is the guest presentation.
- **Life Racing** — designed (raw layer-2 via BPF); the app↔Protocol-Server IPC redirectability is the open unknown.

## Git

Commits use the `milehighideas` GitHub identity (set by `.envrc` via direnv), never a personal account. Conventional Commits.
