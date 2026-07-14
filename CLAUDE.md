# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

marshal bridges device I/O across the Parallels boundary so Windows motorsport tuning apps (AiM RaceStudio 3, Life Racing LifeCal, ECUMaster PMU Client) running on an Apple-Silicon Mac can reach real hardware — Windows-on-ARM can't load the vendors' x64 kernel drivers, so device I/O is relocated to macOS userspace.

The `marshald` Go daemon described in the spec is **not built yet**. Today the repo contains only the design spec and two hardware-discovery/capture kits. Do not invent or run Go build/test/lint commands until a `go.mod` exists.

Authoritative design: @docs/superpowers/specs/2026-07-13-marshal-design.md

## Layout & where code runs

- `tools/usb-discovery/` — macOS kit. Runs **on the Mac host** and needs the real device physically connected. `make help` (the default target) lists the runnable targets; `scan.sh` holds the logic.
- `tools/aim-capture/` — Windows kit. Runs **inside the Parallels guest** (or any Windows PC with RaceStudio 3), not on the Mac.

## Hard constraints

- `tools/aim-capture/capture.ps1` must stay **plain ASCII** — Windows PowerShell 5.1 misparses em-dashes and smart quotes. No Unicode in that file.
- `tools/usb-discovery/scan.sh` uses **only built-in macOS tools** (`system_profiler`, `ioreg`, etc.). No Homebrew, `jq`, or Python dependencies.
- Run `shellcheck` on `scan.sh` before committing shell changes.

## Git

Commits use the `milehighideas` GitHub identity (set by `.envrc` via direnv), never a personal account.
