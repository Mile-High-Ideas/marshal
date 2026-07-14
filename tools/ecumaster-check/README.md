# ECUMaster COM check — run in Windows

This proves the core idea of the whole project on the easiest device. The ECUMaster USB2CAN cable
is a plain **USB serial (COM) device** — Windows-on-ARM already has the driver built in, so it
should "just work" with **no driver install and no bridge**. This check confirms that and tells
you **exactly which COM number** to select in PMU Client.

If PMU Client can read and write the PMU16 through that COM port, the entire marshal approach is
validated — with zero code written.

## Step 0 — connect the cable to Windows (one click on the Mac)

The cable is plugged into the **Mac**, so we tell Parallels to hand it to Windows:

1. Plug the **ECUMaster USB2CAN** cable into the Mac (it powers itself over USB — no car or PMU
   needed just to see the COM port).
2. In the **Parallels menu bar** at the top of the screen: **Devices → USB & Bluetooth →** click
   **`ECUMASTER USB2CAN`** (it may be listed as *STMicroelectronics Virtual COM Port*) so it gets
   a checkmark. That connects it to Windows.
   - If Parallels ever asks *"connect to Mac or Windows?"*, choose **Windows**.

## Step 1 — double-click the check (no typing)

1. Open the `ecumaster-check` folder in Windows.
2. **Double-click `Check ECUMaster.bat`.**
3. A black window runs by itself and finishes with a big message. If all is well it says:

   ```text
   PASS
   The ECUMaster USB2CAN is COM5 via the inbox usbser driver (native ARM64).
   ```

   (Your number may differ — **COM5** is just an example.) It also drops a file named
   **`marshal-ecumaster-check-<date>.zip`** on your Desktop.

If it says **NOT FOUND**, the cable isn't handed to Windows yet — do **Step 0** and run it again.

## Step 2 — the real test in PMU Client

1. Open **PMU Client** — ECUMaster's Windows app you already use to configure the PMU16
   (full name *ECUMaster PMU Client*).
2. In its connection / port setting, choose the **COM number** the check reported.
3. For an actual read/write, the **PMU16 must be powered and wired to the cable's CAN side.**
   With that connected, do a **read configuration**, and a small **write** if you can.

## Step 3 — tell Brandon what happened

Send Brandon:
- the **`.zip`** from your Desktop, **and**
- one line: **did PMU Client read (and write) the PMU over that COM port?**

That yes/no is the whole result — it either proves the bridge approach or tells us to look closer.

## Notes

- **No administrator prompt** and **nothing personal** is collected — just Windows/USB info. Open
  `verdict.txt` (or `ecumaster-device.txt`) inside the zip to read it yourself.
- Already confirmed on the Mac side: this cable is a USB-CDC device, **VID 0x0483 / PID 0x5740**.
  This kit checks the **Windows guest** half of the same story.
