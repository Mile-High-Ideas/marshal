# AiM SW4 capture kit (for Shane — run in Windows)

This tells us the one thing that decides how hard the AiM SW4 is to support: **what kind
of driver RaceStudio 3 uses to talk to the wheel.** It also records exactly how/why the
connection currently fails.

It runs **inside Windows** — your Parallels Windows, or any Windows PC that has RaceStudio 3
installed. **It does not need the connection to work.** Even a failed attempt gives us the
answer.

## Steps

1. Copy this `aim-capture` folder into Windows (drag it into the Parallels Windows desktop,
   or onto a USB stick).
2. If you can, **plug in and power the SW4** first. It only appears when it has **12V**
   (bench harness or in the car) — USB alone won't power it. If you can't power it, that's
   OK, run the kit anyway.
3. **Right-click `RUN.bat` → "Run as administrator"** and let it finish.
   (No admin? Double-clicking still works, just with a little less detail.)
4. It creates a file named **`marshal-aim-capture-DATE.zip`** in this folder. **Send that
   zip back to Brandon.**

That's the whole job.

## What it collects (nothing personal)

- Windows version + whether it's the ARM build.
- The list of USB devices and their status.
- The AiM/SW4 device's details: its driver **service name** and any **error code**.
- AiM's driver `.inf` files and RaceStudio's bundled driver folder.

All of it lands in an `out/` folder next to this README before being zipped. You can open
`out/aim-.../aim-device.txt` to read the result yourself.

## Optional (advanced): capture the actual USB conversation

Only useful **if RaceStudio 3 can successfully connect to the SW4 on that machine** (e.g. a
real x64 Windows PC). If it can:

1. Install **Wireshark** (includes **USBPcap**): <https://www.wireshark.org/download.html>
2. Open Wireshark, start capturing on the **USBPcap** interface that lists the SW4.
3. In RaceStudio 3, connect to the wheel and do a **read configuration** and a small
   **write**.
4. Stop the capture, `File → Save As` a `.pcapng`, and send it to Brandon.

This records the real protocol so marshal can replay it. Skip it if the wheel won't
connect on that machine — the main kit above is what matters first.
