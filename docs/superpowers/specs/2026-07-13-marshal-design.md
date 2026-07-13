# marshal — Mac-side device bridge for motorsport tuning software under Parallels

**Status:** Design approved (2026-07-13)
**Author:** Brandon Shutter (with Claude)
**Language:** Go

---

## 1. Problem

Three Windows tuning applications must connect to hardware from an **Apple Silicon Mac
running Parallels**:

| Software | Device | PC link (confirmed from harness pinouts) |
|---|---|---|
| AiM RaceStudio 3 | SW4 steering wheel | Native **USB** (harness D+/D− breakout; USB‑C cable on MY26) |
| Life Racing LifeCal | Life Racing ECU | **Raw layer‑2 Ethernet** (LAN RX±/TX±), *not* IP |
| ECUMaster PMU Client | PMU16 Autosport | **USB→CAN** cable (owned: `usb-to-can-cable`) |

The apps **run** fine in the guest, but device communication fails. Single root cause:

> **Windows 11 on ARM runs x64 *applications* under user‑mode emulation but cannot load
> x64/x86 *kernel‑mode drivers* — by design.**

All three vendors ship x64‑only kernel drivers (AiM proprietary USB driver; Life Racing's
"Rawether" NDIS protocol driver; ECUMaster's USBtoCAN driver), so none load in the guest.

### Non‑obvious facts established during research
- **SW4 has no Wi‑Fi** — the Wi‑Fi/TCP‑IP workaround that rescues AiM's MX loggers does not apply.
- **LifeCal is raw layer‑2**, mediated by a background "Ethernet Protocol Server" + NDIS driver
  (PCAUSA Rawether). Bridged networking alone is insufficient because the frame plumbing is the
  kernel driver.
- **ECUMaster's cable** may already enumerate as USB‑CDC (inbox ARM64 COM port) — its driver is
  only documented as required for Windows XP/7/8.1. Verifiable on macOS today.
- No vendor ships macOS‑native software.

Sources captured in the research appendix (§10).

## 2. Goal & guiding principle

Let the three apps reach their hardware from the existing Apple‑Silicon + Parallels setup.

**Principle:** *Relocate device I/O to macOS*, where any driver works in userspace, and bridge
only the **app‑level** connection into the guest using **Parallels' own ARM64‑signed virtual
devices**. There is **never a third‑party kernel driver in the guest**.

### Success criteria
- Each device: the vendor app in the guest performs a successful **config read *and* write**
  against real hardware through the bridge.
- The bridge is **reusable**: adding a device = writing one plugin, not re‑architecting.

## 3. Architecture

Three layers.

### 3.1 Guest transport (Parallels built‑ins only)
- **Virtual serial port → host socket** for serial/COM‑style devices. The guest app opens `COMx`;
  Parallels tunnels the byte stream to a macOS socket. No third‑party guest driver — Parallels
  Tools provide the ARM64‑signed serial device.
- **Bridged virtual NIC** for Ethernet / raw‑L2 devices.

### 3.2 `marshald` — macOS daemon
Owns the physical hardware, speaks each device's real protocol, exposes **one host socket per
device** for the guest transport to connect to.
- **USB:** `gousb` (libusb, userspace — no kext).
- **Raw layer‑2:** `gopacket` / BPF.
- Concurrency model: one goroutine set per device, channels between the socket side and the
  device side (byte‑pumping is the daemon's essence).

### 3.3 Device plugins
One Go module per device implementing a small interface:

```go
type Plugin interface {
    Open(ctx context.Context) error          // claim the physical device
    Presentation() Presentation              // COM byte-stream | raw-frame endpoint
    Pump(ctx context.Context, guest io.ReadWriteCloser) error // bridge loop
    Close() error
}
```

### 3.4 Data flow (serial example)
```text
vendor app (guest) → COMx → Parallels vSerial → host socket → marshald plugin → libusb → device
```

## 4. Per‑device tactics

### 4.1 ECUMaster PMU16 — de‑risk first
1. **Discovery (free, today, on the Mac):** read the cable's USB descriptor
   (`system_profiler SPUSBDataType`). Branch:
   - **USB‑CDC** → guest gets inbox ARM64 COM port → **~zero bridge** (pass through or vSerial).
   - **FTDI (VID 0x0403)** → FTDI ARM64 driver in guest → **zero bridge**.
   - **Custom vendor class** → small serial plugin in `marshald`; PEAK PCAN‑USB (~$250, native
     ARM64) only as last resort.
2. Proves the "x64 app under emulation ↔ COM port" spine at minimal cost.

### 4.2 Life Racing / LifeCal — raw layer‑2 bridge
- Reimplement the **frame transport** as a `marshald` plugin that owns the USB‑Ethernet dongle
  via BPF and puts raw frames on the wire.
- Redirect LifeCal's **app ↔ Protocol Server IPC** to the daemon.
- **Decisive unknown:** is that IPC a redirectable localhost socket, or in‑process via the NDIS
  driver? Resolve by capture on the friend's x64 PC (netstat/Process Monitor + the installer's
  Protocol Server binary). Raw frames themselves are fully visible in Wireshark.

### 4.3 AiM SW4 — hardest; discovery gates feasibility
1. **Capture on friend's x64 Windows PC:** VID/PID, the `.inf`/`.sys`, and USB traffic (USBPcap)
   during connect + config read/write.
2. **Branch:**
   - **COM/serial abstraction** (driver exposes a VCP) → same vSerial bridge as ECUMaster. *Best case.*
   - **Raw vendor USB** → `marshald` plugin replaying the RE'd protocol, presented to the guest
     via a user‑mode proxy matching RS3's discovery, or a small **ARM64 UMDF user‑mode driver**
     (user‑mode drivers *can* be ARM64) binding the passed‑through device.
3. **Honest risk:** if RS3 binds tightly to AiM's kernel device interface with an opaque protocol,
   this is a long RE effort or a wall. **Fallback:** a cheap x64 Windows laptop for SW4 config
   only. Decision made after discovery, not before.

## 5. Reverse‑engineering & lab strategy

No new hardware. Captures run on the **friend's existing working x64 Windows PC**, remote‑first:
Claude prepares capture scripts/instructions (USBPcap for AiM, Wireshark for Life Racing, Device
Manager / Process Monitor for driver + IPC identification); friend runs them and returns logs.
The ECUMaster USB descriptor is read locally on Brandon's Mac.

If remote capture proves too slow, revisit a dedicated x86 lab box (also usable as a
VirtualHere/USB‑IP fallback sidecar).

## 6. Build order (de‑risk fast)
1. Scaffold `marshald` core + vSerial bridge → **ECUMaster** working (or confirmed zero‑bridge).
2. **Life Racing** raw‑L2 daemon.
3. **AiM SW4** discovery → decide serial‑bridge vs driver.

## 7. Testing strategy
- **Loopback** (socket ↔ plugin, mock device) — runs on the Mac, no hardware. Covers the transport spine.
- **Protocol‑replay** — record real captures, replay to assert framing/parse correctness.
- **End‑to‑end** — vendor app in guest ↔ real device; validated by a successful config read *and* write.

## 8. Non‑goals (YAGNI)
- No reimplementing vendor GUIs.
- No native‑Mac apps (Approach C) unless a device clearly warrants it later.
- No AiM Wi‑Fi path (SW4 has none).
- No support for device paths the friend does not use.

## 9. Open questions (resolved during work, not blockers)
- ECUMaster cable USB class (answerable today).
- LifeCal ↔ Protocol Server IPC mechanism + raw‑frame EtherType/format.
- RS3 ↔ SW4: COM vs raw USB; driver `.inf`; protocol shape.

## 10. Research appendix — sources
- Windows‑on‑ARM kernel‑driver limitation: Microsoft Windows‑on‑ARM FAQ; Microsoft Q&A on x64 drivers on ARM.
- Parallels USB passthrough / limitations: Parallels KB 129497, KB 128914.
- AiM: memotec SW4 datasheet (pinout, "WiFi: not available"); AiM SW4 page; SW4 manual; AiM RS3 FAQ;
  AiM PC tech‑specs FAQ ("ARM Windows versions are not supported"); Rennlist field report.
- Life Racing / Syvecs: LifeCal manual; Life Racing Quick Start Guide (install log shows Rawether NDIS
  "LfNtSp50"); Syvecs forum threads t=889, t=1164, t=934; Syvecs Wi‑Fi dongle.
- ECUMaster: PMU user manual; USBtoCAN manual; ECUMaster USB‑to‑CAN product/driver page; ECUMaster
  M1/Parallels community thread; PEAK Windows‑on‑ARM announcement + PCAN‑USB.
