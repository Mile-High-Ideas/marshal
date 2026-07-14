# SW4 replay fixture

`sw4_session.ndjson.gz` — a real RaceStudio 3 ↔ SW4 USB session (config **read + write**),
captured with `tools/aim-usbcap` and reduced to one JSON object per meaningful USB frame, in
capture order. Use it for **protocol-replay tests** of the AiM SW4 plugin (design spec §7) so the
plugin can be exercised without hardware.

- 2279 records: **1951 control setups** + **328 bulk data frames**.
- gzip'd (~588 KB); decompress with `compress/gzip` in the test.

## Schema (one object per line)

```json
{"n":1,   "t":"CTRL", "ep":"0x80", "dir":"IN",
 "setup":{"bmRequestType":194,"bRequest":1,"wValue":0,"wIndex":0,"wLength":64}}
{"n":8,   "t":"BULK", "ep":"0x82", "dir":"IN",  "data":"6b6b6b0100000000"}
{"n":3349,"t":"BULK", "ep":"0x01", "dir":"OUT", "data":"0000...."}
```

| field | meaning |
|---|---|
| `n` | source frame number (ordering key) |
| `t` | `"CTRL"` or `"BULK"` |
| `ep` | endpoint address, hex (`0x00`/`0x80` control, `0x01` bulk-out, `0x82` bulk-in) |
| `dir` | `"IN"` (device→host) or `"OUT"` (host→device) |
| `setup` | present on control **submit** frames: the 8-byte SETUP (`bmRequestType` 66=`0x42` OUT / 194=`0xc2` IN, `bRequest` 1=64-byte block / 2=trigger) |
| `data` | present on data-bearing frames: payload as hex |

## Session shape (see `docs/protocols/aim-sw4-usb.md`)

`CTRL` handshake → **read phase** (`BULK IN 0x82`, frames ~8–3348) → **write phase**
(`BULK OUT 0x01`, frames ~3349–4525), `CTRL` throughout.

## Caveats

- **Control data-stage payloads (the 64-byte req-1 blocks) are not in this fixture** — tshark does
  not surface control-transfer data in `usb.capdata`. The `setup` intent is captured; the byte-exact
  data is in the source `bus1.pcapng` if ever needed. A transport-transparent bridge doesn't need
  it (it forwards transfers verbatim); a full emulator would.
- This is **Shane's real PDM config** in wire form (device names, a config path). Fine for this
  private repo; **scrub or synthesize before any public release.**
