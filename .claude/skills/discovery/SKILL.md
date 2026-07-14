---
name: discovery
description: Run and interpret the marshal USB discovery kit (tools/usb-discovery) on the macOS host. Use when the user wants to scan a device (ECUMaster cable, AiM SW4, USB-to-Ethernet adapter), figure out how a device enumerates on the Mac, read a SUMMARY.txt verdict, decide whether a device needs a marshald plugin or gets a free COM port, or build the bundle to send back. Triggers: "run discovery", "scan the SW4/ECUMaster/ethernet", "what does this device need", "read the summary", "make a discovery bundle".
---

# marshal device discovery

The discovery kit lives in `tools/usb-discovery/`. It snapshots macOS USB state
before and after a device is plugged in, diffs them, and writes a per-device
`SUMMARY.txt` with a **verdict** that decides how that device fits the marshal
plan. It uses only built-in macOS tools — nothing to install.

## Before running

- **Must run on the macOS host with the hardware physically attached** (Shane's
  Mac), not in the guest. If you're not on that machine, stop and say so.
- `cd tools/usb-discovery` first. The scan is **interactive**: it prompts the
  operator to unplug (press Enter), then plug in (press Return). You cannot
  complete a scan without a human at the machine doing the physical steps —
  coach them, don't pretend to automate it.

## Commands

| Goal | Command |
|---|---|
| Mac + Parallels info only (no hardware) | `make host` |
| Scan ECUMaster USB→CAN cable | `make ecumaster` |
| Scan AiM SW4 wheel | `make aim` |
| Scan USB→Ethernet adapter (Life Racing) | `make ethernet` |
| Scan any other device | `make scan NAME=<label>` |
| Zip results to send back | `make bundle` |
| Delete all results | `make clean` |

Typical order: `host → ecumaster → aim → ethernet → bundle`. Results land in
`out/<name>-<timestamp>/`; the headline is `out/<name>-<timestamp>/SUMMARY.txt`.

## Device-specific gotchas (state these up front)

- **AiM SW4 needs 12V power to enumerate at all** — connect it to the car with
  ignition/accessory ON (or a 12V bench harness) *before* plugging USB into the
  Mac. A "NO change detected" verdict almost always means it wasn't powered.
- **ECUMaster cable is self-powered over USB** — no car, PMU, or CAN wiring needed.
- **Ethernet adapter** — no ECU or network cable needed for the scan; the run
  also writes `ethernet-detail.txt` (chipset, interface, MAC, MTU, link state).

## Reading the SUMMARY.txt verdict

The verdict line maps directly to the bridging plan:

| Verdict | What it means | marshal implication |
|---|---|---|
| **USB-CDC** (`usbmodem` node) | Inbox ARM64 COM port via usbser.sys | **Best case — zero bridge, zero cost.** |
| **USB-serial** (`usbserial` node) | FTDI / CP210x, vendor ships ARM64 driver | COM port, **zero bridge.** |
| New USB device, **no serial node** | Custom vendor class | Needs a **marshald plugin** (or a supported adapter). Send the bundle. |
| **NO change detected** | Nothing enumerated | Device not powered (SW4 → 12V!), bad cable/port, or not USB. Retry. |

`SUMMARY.txt` also lists the product name, VID/PID (hex + decimal), and any new
`/dev` nodes. If a product was detected, `driver-stack.txt` holds the full
IOService driver stack — the definitive Mac-side driver-model answer.

## Finishing

Run `make bundle` to produce a single `marshal-discovery-<date>.tar.gz` at the
kit root. That one file is what gets sent back for analysis.

For the full end-user, click-by-click instructions, see `tools/usb-discovery/README.md`
and the per-step docs in `tools/usb-discovery/steps/`.
