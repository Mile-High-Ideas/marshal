# AiM SW4 USB capture kit — run in Windows

This records the real USB conversation between **RaceStudio 3** and the **SW4** during a config
read/write. That trace is the one thing left that decides how marshal bridges the SW4 (standard
HID reports vs. AiM's own commands), so it's the single most valuable thing you can send back.

## Where to run it — the old racing laptop, not Parallels

Run this on the machine where **RaceStudio 3 can actually connect to the wheel** — your
**standalone x64 "old racing laptop."** It will **not** work inside Parallels: the SW4's driver is
x64-only, so the wheel can't connect there (that's the whole reason marshal exists).

## One-time setup — install USBPcap (about 2 minutes)

USBPcap is the tool that records USB traffic. It comes bundled with Wireshark:

1. Download Wireshark: <https://www.wireshark.org/download.html>
2. Run the installer. On the **"Choose Components"** screen, make sure **`USBPcap`** is **checked**.
3. Finish the install and **reboot if it asks** (the capture driver needs it).

You only ever do this once.

## Do the capture (double-click)

1. **Power the SW4** (12V — it needs the car ignition/accessory on or a bench harness) and plug its
   USB into the laptop.
2. Open the `aim-usbcap` folder and **double-click `Capture SW4 Traffic.bat`.**
3. Click **"Yes"** on the administrator popup (USBPcap needs it).
4. It says **CAPTURING**. Now switch to **RaceStudio 3** and:
   - **Connect** to the SW4,
   - do a **read configuration**,
   - do a **small write** (change one setting and send it).
5. Come back to the black window and **press Enter** to stop.
6. It drops **`marshal-aim-usbcap-<date>.zip`** on your Desktop. **Send that one file to Brandon.**

## Notes

- The read **and** the write in one capture is ideal — the write is what proves the full round trip.
- To keep it foolproof, it records **all** USB buses for the few seconds of the read/write (no bus
  to pick), so **don't type any passwords** until you've pressed Enter to stop. Brandon keeps only
  the wheel's packets.
- If the window says the capture looks **nearly empty**, the RS3 read/write didn't actually run —
  just double-click and do it again.
- Nothing is uploaded anywhere; the `.zip` is a local file you choose to send.
