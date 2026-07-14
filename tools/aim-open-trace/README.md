# AiM SW4 "how RS3 opens the wheel" trace — run in Windows

The SW4 **device side** is already solved (marshal owns the wheel over libusb, and the USB protocol
is decoded — see `docs/protocols/aim-sw4-usb.md`). The one open piece is the **guest presentation**:
how RaceStudio 3 running *inside* the Windows guest reaches marshal. To build that, we need to know
**exactly how RS3 opens the SW4 on Windows** — the device path/handle it uses — so a small guest-side
shim can present the same thing and forward the traffic to the Mac.

This is a **short capture**, and it's separate from the USB traffic capture you already did.

Run it on the **standalone x64 laptop** where **RS3 connects to the wheel**.

## One-time setup

**Process Monitor** — <https://learn.microsoft.com/sysinternals/downloads/procmon> (single `.exe`,
no install; unzip it). If you already grabbed it for the Life Racing kit, reuse it.

## Do the trace

1. **Power the SW4** (12V) and plug its USB into the laptop. **Do not open RS3 yet.**
2. Start **Process Monitor** (as administrator).
3. Set a filter so it's readable: **Filter -> Filter…**, add
   **`Process Name` is `RaceStudio3.exe`** -> **Include** -> OK. (If the RS3 process has a different
   name, use whatever shows in Task Manager.)
4. Open **RS3** and **connect to the SW4** (a config **read** is enough).
5. In Process Monitor, look at the first **`CreateFile`** operations RS3 does that succeed on a
   device — the **Path** column is what we need. It'll look like one of:
   - `\\?\HID#VID_11CC&PID_0110#…` (a HID device path), or
   - `\\.\AIM…` or `\\?\USB#VID_11CC&PID_0110#…\{…GUID…}` (a device-interface / symbolic-link name).
6. **File -> Save…**, **"All events"**, format **PML** or **CSV**, save to the Desktop as
   `procmon-rs3-open`.

## Send it back

- `procmon-rs3-open.PML` (or `.CSV`).
- If it's obvious, just tell Brandon the **exact Path** of the `CreateFile` RS3 uses to open the wheel.

## What this unblocks (and what it does not)

This gives the **input** for the guest-presentation design, not the design itself. Once we know how
RS3 opens the wheel, the remaining decision is the *mechanism* — and that's a call Brandon makes, not
a capture:

- **ARM64 UMDF user-mode driver** in the guest that impersonates the SW4's device interface and
  forwards each transfer to marshal over the §7 socket framing (user-mode drivers *can* be ARM64), or
- a **user-mode proxy/shim** that matches how RS3 opens the device.

That decision is its own brainstorm/spec; this trace is the fact it needs.
