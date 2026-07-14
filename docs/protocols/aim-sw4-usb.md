# AiM SW4 ↔ RaceStudio 3 USB protocol (reverse-engineered)

**Status:** v1, reverse-engineered 2026-07-13 from a single USBPcap capture of an RS3
config **read + write** on Shane's x64 laptop (`bus1.pcapng`, 4558 USB frames).

**There is no public documentation for this protocol.** AiM's config USB link is undocumented;
their "Open Systems" program is CAN-only, and the on-disk `.aimcfg` file is a proprietary container
that others gave up hand-editing. This document plus the capture are the only spec that exists.

---

## The one thing that matters for the bridge

**The bridge is transport-transparent.** `marshald` forwards USB transfers between RS3 (in the
guest) and the wheel (on the Mac); it does **not** need to understand the payload. To build the
bridge we only need the **transport model** (endpoints, transfer types, control-request shape) —
which is fully captured below. The payload framing (§4) is documented for **test fixtures and
validation only**, not because the bridge must parse it.

## 1. Device identity

- **USB `VID 0x11CC` (AiM s.r.l.) / PID 0x0110`.**
- Interface is HID-class *shell* with vendor values: `bInterfaceClass 0x03 / SubClass 0x06 /
  Protocol 0x50`. Windows binds AiM's kernel driver `AIM_USBdriver_0110` by exact VID/PID; the HID
  class is not used as a data path (zero interrupt/HID-report traffic).
- On macOS: ownable in userspace via **libusb** (control + bulk). No kext.

## 2. Endpoints & transfer types

| Pipe | Transfer | Direction | Role |
|---|---|---|---|
| **EP0** | Control (vendor) | both | command / handshake / coordination |
| **EP `0x01`** | Bulk | OUT (host→wheel) | config **write** (upload) |
| **EP `0x82`** | Bulk | IN (wheel→host) | config **read** (download) |

No isochronous, no interrupt. All data rides bulk `0x01`/`0x82`; EP0 coordinates.

## 3. Control channel (EP0, vendor requests)

`bmRequestType` is **vendor / recipient=endpoint**: `0x42` for OUT, `0xc2` for IN.

| bRequest | wLength | wValue | wIndex | Meaning (working model) |
|---|---|---|---|---|
| **1** | 64 | 0 | 0 | 64-byte command/status block (seen both IN and OUT) |
| **2** | 0 | 0 | 0..4 | trigger / select (no data); `wIndex` usually 0 |

> The exact semantics of the 64-byte req-1 blocks are not fully decoded. For a **faithful bridge**
> this does not matter — forward each control transfer verbatim. For a **replay/emulation** they
> must be reproduced; derive them from the capture during implementation.

## 4. Bulk payload framing (for test fixtures only)

AiM's text/tag protocol. Sections are introduced by a fixed-width header, then a body:

```tsx
<h<TAG><10-digit length>a>\r\n      section header (TAG is 4-5 chars, space-padded)
<body>                               key=value|… lines and/or an XML block
```

Example (from the write/upload stream):

```tsx
<hCfgT0000000123a>
<hCfgI0000000089a>
cfg_dir=0|
cfg_name=SW014 PDM Norton 2025v1 01|
uid=1720540809|
sw_uid=1720540603|
<?xml version="1.0"?>
<Cfgs_table>
  <e c="ElencoCfgHWRel" i="ElencoCfgHWRel.1">
    <p n="CfgName">SW014 PDM Norton 2025v1 01</p>
    ...
```

- The 10-digit field is a zero-padded length of the following body (decimal; confirm during impl).
- Body is either pipe-delimited `key=value|` or a nested `<?xml …><Cfgs_table>…` block.
- **Section tag catalog** seen (each = a wheel subsystem): `CfgT` `CfgI` (config metadata),
  `DAL`/`DAP`/`LDAL`/`LDAP` (alarms), `LEDF` (LEDs), `PPMF`, `ANA` (analog), `CHD`/`SENS` (channels/
  sensors), `MAT` (math), `DSL`/`Digi` (display), `FNZ` (functions), `GMas`, `SHLF`, `OVL`, …
- **Read (bulk IN) records** are chunked with a marker `6b 6b 6b 01` (ASCII `kkk`\x01) followed by a
  4-byte incrementing counter, then body bytes. ~87 such records in the sample read stream.

## 5. Session flow (observed)

1. **Handshake** — EP0 vendor control exchanges (req 1 / req 2) from frame 1.
2. **Read phase** (frames ~8–3348) — bulk IN `0x82`: RS3 downloads the wheel's current config.
3. **Write phase** (frames ~3349–4525) — bulk OUT `0x01`: RS3 uploads the (modified) config.
   Control transfers continue throughout, bracketing the bulk activity.

## 6. macOS device-side (libusb / gousb) notes

- Open `0x11CC:0x0110`, detach the kernel HID driver if macOS claimed it, claim the interface.
- Implement: `controlTransfer(0x42, 1, 0, 0, buf64)` / `controlTransfer(0xc2, 1, …)`,
  `controlTransfer(0x42, 2, 0, wIndex, empty)`, `bulkOut(0x01, …)`, `bulkIn(0x82, …)`.
- The plugin is a **transfer relay**, not a byte pump — this does **not** fit the current
  `COMByteStream` presentation. It needs a new USB-transfer presentation/transport (see design spec
  §4.3 "guest presentation").

## 7. Recommended guest-transport framing (for `Pump`)

The SW4 plugin's `Pump(ctx, guest)` cannot be a byte pump — the guest side sends **USB transfers**,
not a byte stream. Recommended minimal request/response framing over the guest Unix socket (the
guest-side forwarder speaks the same). All integers little-endian:

```bash
Request  (guest -> host):
  u8  kind          1 = CONTROL, 2 = BULK
  u8  endpoint      0x00/0x80 (control dir in bit7), 0x01, 0x82
  u16 _reserved
  // CONTROL only (kind==1): the 8-byte SETUP
  u8  bmRequestType ; u8 bRequest ; u16 wValue ; u16 wIndex ; u16 wLength
  u32 outLen        length of OUT payload that follows (0 for IN transfers)
  u8  out[outLen]

Response (host -> guest):
  i32 status        libusb transfer status (0 = LIBUSB_SUCCESS)
  u32 inLen
  u8  in[inLen]     IN payload (control-IN / bulk-IN); empty for OUT
```

The plugin decodes a request, issues the matching `libusb` call (§6), and writes the response. This
is a thin, transport-transparent relay — it never parses the AiM payload. (USB/IP is the heavyweight
standard alternative; this custom framing is smaller and sufficient for one device.) A new
`Presentation` value — e.g. `USBTransferEndpoint` — should back it.

## 8. Replay fixture (build/test without hardware)

`internal/plugins/aim/testdata/sw4_session.ndjson.gz` — the real captured session as one JSON object
per USB frame (2279 records). Schema and usage: that directory's `README.md`. Drive a replay test
by feeding each record's transfer through the framing above against a mock `libusb` device and
asserting the plugin relays it faithfully.

## 9. Ground truth & re-derivation

Capture: `scratchpad/.../bus1.pcapng` (= `\\.\USBPcap4`), device address 1. Re-derive with:

```sh
tshark -r bus1.pcapng -T fields -e usb.transfer_type -e usb.endpoint_address -e usb.data_len
tshark -r bus1.pcapng -Y "usb.endpoint_address==0x01 && usb.capdata" -T fields -e usb.capdata  # write
tshark -r bus1.pcapng -Y "usb.endpoint_address==0x82 && usb.capdata" -T fields -e usb.capdata  # read
```

## 10. SW4 plugin — implementation checklist (Go)

> **Implemented (2026-07-14):** steps 1–6 are done — see `internal/plugins/aim/`
> (the libusb device is behind a `//go:build aim_usb` tag; the replay test validates
> the fixture with no hardware). Step 7 (the Windows-side forwarder) remains out of
> scope for the plugin.

Everything below is buildable from this doc + the fixture, no hardware:

1. Add a libusb binding dependency (`github.com/google/gousb`) to `go.mod`.
2. Add `Presentation` value `USBTransferEndpoint` (`internal/plugin`).
3. New package `internal/plugins/aim`:
   - `Open`: find `0x11CC:0x0110`, detach the kernel HID driver if bound, claim the interface
     (interface 0; endpoints `0x01` bulk-out, `0x82` bulk-in, plus EP0) — gousb reads the config
     descriptor live, so confirm the layout at open rather than hard-coding.
   - `Pump`: loop — decode a request frame (§7), issue the matching control/bulk transfer (§6),
     write the response frame. Transport-transparent; never parse the payload.
   - `Close`: release interface, close device.
4. Register the type (e.g. `"aim-sw4"`) in `cmd/marshald/main.go`.
5. Config: a device `type = "aim-sw4"` (VID/PID default to `0x11CC/0x0110`, overridable).
6. Replay test: load `testdata/sw4_session.ndjson.gz`, drive `Pump` against a mock libusb device,
   assert each recorded transfer is relayed faithfully (respect the read-tick idle contract).
7. **Out of scope for the plugin:** the Windows-side forwarder that makes RS3 speak the §7 framing —
   that's the separate guest-presentation design problem.

## 11. Open items

- Decode the 64-byte req-1 control blocks (needed only for emulation/replay, not for a pass-through bridge).
- Confirm the header length field (decimal vs hex) and whether it counts the CRLF.
- Capture a **connect-only** and a **read-only** session to separate handshake from data phases cleanly.
- The **guest-presentation** transport (how RS3-in-guest reaches `marshald`) remains the open design
  question — this doc defines *what* must be forwarded, not *how* it enters the guest.
