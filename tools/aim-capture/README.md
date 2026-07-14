# AiM SW4 capture kit — run in Windows

This runs **inside Windows** (your Parallels Windows, or any Windows PC that has RaceStudio 3).
It tells us the one thing that decides how hard the SW4 is to support: **what kind of driver
RaceStudio 3 uses**, plus exactly how the connection currently fails. **It does not need the
connection to work** — even a failed attempt gives us the answer.

## Do this (all double-click, no typing)

1. **Get this `aim-capture` folder into Windows.** Easiest: drag the folder onto the Parallels
   Windows desktop (or copy it via a USB stick).
2. **Power up the SW4.** The wheel only reports fully when it has 12V — have it **connected to
   the car with the ignition/accessory ON**, or on a **12V bench harness**, then plug its USB in.
   (No power? Still run it — we'll just get less.)
3. In Windows, open the `aim-capture` folder and **double-click `Capture AiM SW4.bat`.**
4. Two popups may appear — both are normal:
   - If you see **"Windows protected your PC"** (blue box), click **"More info"** → **"Run
     anyway."**
   - Then **"Do you want to allow this app to make changes?"** — **click "Yes."** (That's just
     so it can read the full driver list.)
5. A black window runs by itself and finishes with a message. It creates a file named
   **`marshal-aim-capture-<date>.zip`** in the folder.
6. **Send that one `.zip` to Brandon** (drag into Messages, or attach to an email).

That's the whole job.

## What it collects (nothing personal)

Windows version + whether it's the ARM build, the list of USB devices and their status, the
AiM/SW4 device's **driver name** and any **error code**, and AiM's driver files. All of it goes
into an `out/` folder before being zipped — you can open `out\aim-...\aim-device.txt` to read it
yourself.

## Optional (only if the wheel actually connects on that PC)

If RaceStudio 3 can successfully connect to the SW4 on that machine, we can also record the real
conversation between them:

1. Install **Wireshark** (it includes "USBPcap"): <https://www.wireshark.org/download.html>
2. Open Wireshark, start capturing on the **USBPcap** interface that lists the SW4.
3. In RaceStudio 3, connect and do a **read configuration** (and a small **write** if you can).
4. Stop, `File → Save As` a `.pcapng`, and send it to Brandon.

Skip this if the wheel won't connect on that PC — the double-click step above is what matters
first.
