# AiM SW4 "how RS3 opens the wheel" trace — run in Windows

The SW4 **device side** is already solved (marshal owns the wheel over libusb and the USB protocol is
decoded — see `docs/protocols/aim-sw4-usb.md`). The one open piece is the **guest presentation**: how
RaceStudio 3 running *inside* the Windows guest reaches marshal. To build that, we need the exact way
RS3 **opens the SW4 on Windows** — the device path/handle — so a guest-side shim can present the same.

This is a **short, separate** capture from the USB traffic one you already did.

Run it on the **standalone x64 laptop** where **RS3 connects to the wheel** (not the Parallels guest).

## Do the capture (double-click)

1. **Power the SW4** (12V) and plug its USB into the laptop.
2. Open the `aim-open-trace` folder and **double-click `Trace SW4 Open.bat`.**
3. Click **"Yes"** on the administrator popup. If Windows shows a blue **"Windows protected your PC"**
   box, click **More info -> Run anyway** (the file is just a script, unsigned).
4. It fetches Process Monitor automatically and says **LOGGING**. Now switch to **RaceStudio 3** and
   **connect to the SW4** (a config **read** is enough).
5. Come back to the black window and **press Enter** to stop.
6. It drops **`marshal-aim-open-trace-<date>.zip`** on your Desktop. **Send that one file to Brandon.**

## Notes

- Needs internet the first time, to download Process Monitor. **No internet?** Grab it once from
  <https://learn.microsoft.com/sysinternals/downloads/procmon>, unzip **`Procmon.exe`** into this
  `aim-open-trace` folder, and run the `.bat` again.
- Keep it short — just the connect. Don't type any passwords while it's logging.
- Nothing is uploaded anywhere; the `.zip` is a local file you choose to send.

## What this unblocks (and what it does not)

This gives the **input** for the guest-presentation design, not the design itself. Once we know how RS3
opens the wheel, the remaining decision is the *mechanism* — Brandon's call, not a capture:

- an **ARM64 UMDF user-mode driver** in the guest that impersonates the SW4's device and forwards each
  transfer to marshal over the §7 socket framing (user-mode drivers *can* be ARM64), or
- a **user-mode proxy/shim** matching how RS3 opens the device.

That decision is its own brainstorm/spec; this trace is the fact it needs.
