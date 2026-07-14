# marshal — Mac-side device bridge for motorsport tuning software under Parallels

**Status:** Design approved (2026-07-13)
**Author:** Brandon Shutter (with Claude)
**Language:** Go
**Findings:** 2026-07-13 — ECUMaster confirmed USB‑CDC (§4.1); SW4 confirmed raw vendor USB, HID‑class, x64‑only driver (§4.3). Device IDs and open gates in‑section.

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
1. **Discovery (free, on Shane's Mac):** read the cable's USB descriptor
   (`system_profiler SPUSBDataType`). Branch:
   - **USB‑CDC** → guest gets inbox ARM64 COM port → **~zero bridge** (pass through or vSerial).
   - **FTDI (VID 0x0403)** → FTDI ARM64 driver in guest → **zero bridge**.
   - **Custom vendor class** → small serial plugin in `marshald`; PEAK PCAN‑USB (~$250, native
     ARM64) only as last resort.
2. Proves the "x64 app under emulation ↔ COM port" spine at minimal cost.

> **Confirmed (2026‑07‑13, Shane's Mac):** device "ECUMASTER USB2CAN", **VID 0x0483 / PID 0x5740**
> = STM32 Virtual COM Port (USB CDC‑ACM), enumerates as `/dev/cu.usbmodem*`. On Win11 ARM this
> binds the **inbox `usbser.sys` (native ARM64) COM port — zero driver, zero bridge.**
>
> **Guest‑side confirmed (2026‑07‑13, Shane's Parallels Win11‑ARM guest, `tools/ecumaster-check`):**
> passed the cable through Parallels; it bound the **inbox `usbser` (native ARM64)** and presented
> **COM3** — verdict **PASS**, no third‑party driver. The transport spine is proven at the plumbing
> level: **no `marshald` needed for this device.** Only step left is the app‑level **PMU Client read
> + write over COM3** (needs the PMU16 powered and wired to the cable's CAN1 side).

### 4.2 Life Racing / LifeCal — raw layer‑2 bridge
- Reimplement the **frame transport** as a `marshald` plugin that owns the USB‑Ethernet dongle
  via BPF and puts raw frames on the wire.
- Redirect LifeCal's **app ↔ Protocol Server IPC** to the daemon.
- **Decisive unknown:** is that IPC a redirectable localhost socket, or in‑process via the NDIS
  driver? Resolve by capture on Shane's standalone x64 PC (netstat/Process Monitor + the installer's
  Protocol Server binary). Raw frames themselves are fully visible in Wireshark.

### 4.3 AiM SW4 — hardest; discovery gates feasibility
1. **Capture** VID/PID, the `.inf`/`.sys`, and USB traffic (USBPcap) during connect + config
   read/write. Enumeration/driver‑model info comes from any Windows env (even the ARM guest); the
   **protocol** USBPcap must come from a machine where RS3 actually connects — Shane's
   **standalone x64 Windows PC**.
2. **Branch:**
   - **COM/serial abstraction** (driver exposes a VCP) → same vSerial bridge as ECUMaster. *Best case.*
   - **Raw vendor USB** → `marshald` plugin replaying the RE'd protocol, presented to the guest
     via a user‑mode proxy matching RS3's discovery, or a small **ARM64 UMDF user‑mode driver**
     (user‑mode drivers *can* be ARM64) binding the passed‑through device.
3. **Honest risk:** if RS3 binds tightly to AiM's kernel device interface with an opaque protocol,
   this is a long RE effort or a wall. **Fallback:** a cheap x64 Windows laptop for SW4 config
   only. Decision made after discovery, not before.

> **Confirmed (2026‑07‑13, run inside Shane's Parallels Win11‑ARM guest):** SW4 = **VID 0x11CC
> (AiM s.r.l.) / PID 0x0110**. AiM ships a **custom kernel‑mode function driver**
> `AIM_USBdrv_11CC_0110_64a.sys` (inf `oem9.inf` / `aim_usbdrv_11cc_0110_64a.inf`), `Class=HIDClass`,
> **x64‑only (`NTamd64`, no ARM64 variant)**, DriverVer 2013 v64.01, WHQL‑signed. In the ARM guest
> the wheel **enumerates over USB passthrough as a HID node** but the driver won't start
> (`CM_PROB_FAILED_START`) — first‑hand proof of the root cause in the real target environment, and
> confirmation that **Parallels passes the SW4's USB through to the guest**.
>
> **Branch decision:** not a COM/VCP → this is **raw vendor USB, but the friendly HID‑class
> variant.** Because the device is HID at the wire level, **macOS owns it in userspace via
> IOHIDManager/hidapi — no kext, no libusb detach.** The Mac‑owns‑device half is effectively de‑risked.
>
> **Still open (the real gate):** RS3 was **not installed** on that guest, so there is no protocol
> USBPcap yet. Need a read+write trace from Shane's **standalone x64 PC** to decide the guest
> presentation: standard HID reports (simple bridge) vs AiM's custom device‑interface IOCTLs
> (needs an ARM64 UMDF user‑mode driver or proxy).

> **Confirmed (2026‑07‑13, second run on Shane's standalone x64 Win11 PC):** on real x64 the SW4
> **works** — `Status OK`, `CM_PROB_NONE`, and AiM's kernel service **`AIM_USBdriver_0110` is
> Running** (`AIM_USBdrv_11CC_0110_64a.sys`). This is the **working reference environment**, so a
> USBPcap read/write trace is feasible here. New detail from the descriptor `CompatibleIds`: the
> interface is **HID class 0x03, vendor subclass 0x06, protocol 0x50** — a vendor‑custom HID
> interface. The driver inf (`oem53.inf`, byte‑identical to the guest's `oem9.inf`) registers **only
> a kernel service — no device‑interface GUID** — so RS3 reaches the wheel via the HID collection
> or a fixed device name the `.sys` creates, not a registered interface class. **Still missing:** the
> actual USBPcap traffic (this run was the enumeration kit, no USB capture), and RS3 itself is **not
> under Program Files** on that box despite the driver being installed — Shane needs RS3 present +
> a Wireshark/USBPcap read+write.

> **PROTOCOL DECODED (2026‑07‑13, USBPcap of an RS3 read+write on the x64 box):** the open question
> is answered — **RS3 does NOT use standard HID.** There is **zero** interrupt/HID‑report traffic.
> The wheel is driven by:
> - **Vendor control requests on EP0** — `bmRequestType 0x42` (vendor, host→device, recipient =
>   endpoint), `bRequest 1` carrying a 64‑byte command block, `bRequest 2` as a trigger/select with
>   `wIndex` (0..4). No `GET/SET_REPORT`.
> - **Bulk OUT `0x01`** (host→wheel, config *write*) and **Bulk IN `0x82`** (wheel→host, config
>   *read*), including multi‑KB and 63 KB transfers.
>
> **Payload is AiM's text/tag protocol, largely ASCII/XML** — very RE‑friendly. Writes are framed as
> `<hSECTION<hexlen>a>\r\n` headers wrapping `<?xml version="1.0"?><Cfgs_table>…` and `key=value`
> config, with named sections (`CfgT`, `CfgI`, `CHSF`, `LEDF`, `LDAL`, `DAL`, `PPMF`, `OVL1`,
> `GMas`, …). Reads are binary records prefixed with ASCII `kkk`\x01 + an incrementing counter.
>
> **Consequences:** (1) macOS/`marshald` owns this trivially via **libusb** — vendor control + bulk,
> no HID, no kext. (2) A "standard HID bridge" is **off the table**; the SW4 plugin replays these
> exact transfers. (3) The **guest‑presentation** question stands, but is now concrete: forward
> control(`0x42`/req1/req2) + bulk(`0x01`/`0x82`) to RS3, either via an ARM64 UMDF user‑mode driver
> exposing AiM's device or a shim matching how RS3 opens the `.sys`.

## 5. Reverse‑engineering & lab strategy

No new hardware bought. **Brandon has no devices** — all hardware lives with **Shane**, who owns
the full rig: an **Apple‑Silicon Mac running Parallels** (the real target environment) and a
**standalone x64 Windows PC** where the vendor apps/drivers currently load. Shane **clones the repo
and follows the kit instructions**, then returns logs; Brandon builds `marshald` from them.

- **Mac‑side enumeration** (how a device talks to macOS): `tools/usb-discovery/` on Shane's Mac.
- **Windows driver/enumeration** (VID/PID, `.inf`/`.sys`, failure code): `tools/aim-capture/` —
  runs in any Windows env, including the Parallels ARM guest (that's where the 2026‑07‑13 AiM run
  happened).
- **Protocol capture** (USBPcap for AiM, Wireshark for Life Racing, Process Monitor for IPC): must
  run where the app actually connects — Shane's **standalone x64 PC**.

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
- No support for device paths Shane does not use.

## 9. Open questions (resolved during work, not blockers)
- ~~ECUMaster cable USB class~~ — **RESOLVED (2026‑07‑13):** USB CDC‑ACM (VID 0x0483 / PID 0x5740),
  free inbox ARM64 COM port. See §4.1.
- LifeCal ↔ Protocol Server IPC mechanism + raw‑frame EtherType/format.
- RS3 ↔ SW4: **partly RESOLVED (2026‑07‑13):** not COM — **raw vendor USB, HID‑class**; driver is
  AiM's x64‑only `AIM_USBdrv_11CC_0110_64a.sys` (VID 0x11CC / PID 0x0110). **Still open:** protocol
  shape + whether RS3 uses standard HID reports or AiM's custom IOCTLs (needs an x64 USBPcap). See §4.3.

## 10. Research appendix — sources
- Windows‑on‑ARM kernel‑driver limitation: Microsoft Windows‑on‑ARM FAQ; Microsoft Q&A on x64 drivers on ARM.
- Parallels USB passthrough / limitations: Parallels KB 129497, KB 128914.
- AiM: memotec SW4 datasheet (pinout, "WiFi: not available"); AiM SW4 page; SW4 manual; AiM RS3 FAQ;
  AiM PC tech‑specs FAQ ("ARM Windows versions are not supported"); Rennlist field report.
- Life Racing / Syvecs: LifeCal manual; Life Racing Quick Start Guide (install log shows Rawether NDIS
  "LfNtSp50"); Syvecs forum threads t=889, t=1164, t=934; Syvecs Wi‑Fi dongle.
- ECUMaster: PMU user manual; USBtoCAN manual; ECUMaster USB‑to‑CAN product/driver page; ECUMaster
  M1/Parallels community thread; PEAK Windows‑on‑ARM announcement + PCAN‑USB.
