# Life Racing / LifeCal capture kit — run in Windows

This gathers the two things that decide how marshal bridges the **Life Racing ECU**. The LifeCal
plugin is blocked on both — with this capture it becomes buildable (the way the SW4 USB capture
unblocked that plugin).

Run it on your **standalone x64 "old racing laptop"** — the machine where **LifeCal actually connects
to the ECU**. It will not work inside Parallels (that's the whole reason marshal exists).

## What it records

1. **How LifeCal reaches its "Ethernet Protocol Server."** LifeCal doesn't touch the ECU directly — a
   background **Protocol Server** (installed with LifeCal; it uses a raw-Ethernet "Rawether" driver)
   does the wire I/O, and LifeCal talks to *that*. If that link is a **localhost socket**, marshal
   slots in cleanly; if it's **in-process / through the driver**, it's a harder road. This capture
   (Process Monitor + netstat) tells us which — the decisive unknown.
2. **The raw frames** — captured with **Wireshark's `dumpcap`** (already installed here from the SW4
   USB test) for a reliable `.pcapng`, falling back to a built-in `netsh` trace if Wireshark isn't
   found — so the Mac side can reproduce them.

## Do the capture (double-click)

1. Have the ECU **powered and connected** to the laptop through the usual USB-to-Ethernet adapter.
2. Open the `lifecal-capture` folder and **double-click `Capture LifeCal.bat`.**
3. Click **"Yes"** on the administrator popup. If Windows shows a blue **"Windows protected your PC"**
   box, click **More info -> Run anyway** (the file is just a script, unsigned).
4. It fetches Process Monitor automatically and says **LOGGING**. Now switch to **LifeCal** and:
   - **connect** to the ECU,
   - do a config **read**,
   - do a small **write** (change one setting and send it).
5. Come back to the black window and **press Enter** to stop. (The packet trace takes a minute to
   finish — let it.)
6. It drops **`marshal-lifecal-capture-<date>.zip`** on your Desktop. **Send that one file to Brandon.**

## Notes

- Needs internet the first time, to download Process Monitor. **No internet?** Grab it once from
  <https://learn.microsoft.com/sysinternals/downloads/procmon>, unzip **`Procmon.exe`** into this
  `lifecal-capture` folder, and run the `.bat` again.
- The read **and** the write in one go is ideal — the write proves the full round trip.
- Don't type any passwords while it's logging (it records network + process activity for those
  seconds). Brandon keeps only what's relevant.
- Nothing is uploaded anywhere; the `.zip` is a local file you choose to send.
