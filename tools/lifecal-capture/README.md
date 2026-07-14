# Life Racing / LifeCal capture kit — run in Windows

This gathers the two things that decide how marshal bridges the **Life Racing ECU**. Right now the
LifeCal plugin is blocked on both — with these captures, it becomes buildable (the same way the SW4
USB capture unblocked that plugin).

Run everything on your **standalone x64 "old racing laptop"** — the machine where **LifeCal
actually connects to the ECU**. It will not work inside Parallels (that's the whole reason marshal
exists).

## What we're trying to learn

1. **Is LifeCal's link to its "Ethernet Protocol Server" redirectable?** LifeCal doesn't talk to the
   ECU directly — a background **Protocol Server** (installed with LifeCal, it uses a raw-Ethernet
   "Rawether" driver) does the wire I/O, and LifeCal talks to *that*. If LifeCal reaches the Protocol
   Server over a **localhost network socket**, marshal can slot in cleanly. If it's **in-process /
   through the driver**, it's a harder road. This capture tells us which.
2. **What the raw frames look like** — the actual bytes LifeCal/ECU exchange, so the Mac side can
   reproduce them.

## One-time setup (about 5 minutes)

1. **Wireshark** — <https://www.wireshark.org/download.html>. Default install is fine (you don't need
   USBPcap this time; you need the normal network capture, Npcap, which the installer offers — leave
   it checked).
2. **Process Monitor** — <https://learn.microsoft.com/sysinternals/downloads/procmon>. It's a single
   `.exe`, no install; just unzip it.

You only do this once.

## Capture A — how LifeCal reaches the Protocol Server (Process Monitor + netstat)

1. Have the ECU **powered and connected** to the laptop through the usual USB-to-Ethernet adapter,
   but **do not open LifeCal yet.**
2. Open a **Command Prompt** and run:  `netstat -ano -b > %USERPROFILE%\Desktop\netstat-before.txt`
   (right-click Command Prompt -> "Run as administrator" so `-b` shows program names).
3. Start **Process Monitor** (as administrator). It starts capturing immediately. Leave it running.
4. Open **LifeCal** and **connect to the ECU** (do a config **read**, then a small **write** if you
   can — same as a normal session).
5. Back in Command Prompt run:  `netstat -ano -b > %USERPROFILE%\Desktop\netstat-during.txt`
6. In Process Monitor: **File -> Save…**, choose **"All events"**, format **PML** (native) or **CSV**,
   save to the Desktop as `procmon-lifecal`.
7. In **Task Manager -> Details**, note the process that is the **Protocol Server** (something like a
   service or a background `*ProtocolServer*` / Rawether helper). Right-click it -> **Open file
   location**, and note the **full path** of that `.exe`.

*(What Brandon reads from this: whether LifeCal and the Protocol Server exchange data over
`127.0.0.1` sockets — redirectable — or via `DeviceIoControl` to the Rawether driver / a named pipe /
shared memory — in-process.)*

## Capture B — the raw frames (Wireshark)

1. With the ECU still connected, open **Wireshark**.
2. In the interface list, pick the **USB-to-Ethernet adapter** (its name shows the adapter chipset;
   it's the one that appears/disappears when you unplug the adapter — not "Wi-Fi" or the built-in NIC).
3. Click the blue **shark-fin** to start capturing.
4. Switch to **LifeCal** and do a **config read**, then a **small write**.
5. Stop the capture (red square). **File -> Save As…**, save to the Desktop as `lifecal-frames.pcapng`.

*(These frames are raw layer-2, not IP; Wireshark shows them fine. Brandon reads the EtherType and
frame format from here.)*

## Send it back

Put these on the Desktop and email/zip them to Brandon:

- `lifecal-frames.pcapng`
- `procmon-lifecal.PML` (or `.CSV`)
- `netstat-before.txt` and `netstat-during.txt`
- the **full path** of the Protocol Server `.exe` (and, if easy, a copy of it) + the LifeCal
  **install log** if you still have it.

## Notes

- The read **and** the write in one go is ideal — the write proves the full round trip.
- Nothing is uploaded anywhere; these are local files you choose to send.
- A double-click launcher (like the other kits' `.bat`) can be added later to automate this; for now
  the manual steps above are exact.
