# USB discovery kit (for Shane)

This little tool figures out **how each device talks to the computer**, which tells us
whether it will work on an Apple-Silicon Mac in Parallels with little or no extra software.

You run it on your **Mac** (not inside Windows). It only uses tools that already come with
macOS — nothing to install.

## What you need

- The Mac you normally use with Parallels.
- The device you want to check, plus its normal cable.
- A Terminal window. (Press `Cmd`+`Space`, type `Terminal`, hit Enter.)

## How to run it

1. In Terminal, go into this folder:

   ```bash
   cd path/to/tools/usb-discovery
   ```

2. Run one device at a time. Follow the on-screen prompts (it asks you to unplug, then
   plug in the device):

   ```bash
   make ecumaster     # the ECUMaster USB-to-CAN cable
   make aim           # the AiM SW4 steering wheel
   make ethernet      # the USB-to-Ethernet adapter you use for Life Racing / LifeCal
   ```

3. When you've done the ones you can, package everything up:

   ```text
   make bundle
   ```

   That creates a single file named `marshal-discovery-DATE.tar.gz`. **Send that file
   back to Brandon.**

That's it. `make help` lists everything.

## Important notes per device

- **ECUMaster USB-to-CAN cable** — powers itself over USB. Just plug it into the Mac; you
  do **not** need the car or the PMU connected for this check.
- **USB-to-Ethernet adapter** (Life Racing) — also powers itself over USB. Plug just the
  adapter in; the ECU/network cable doesn't need to be attached.
- **AiM SW4** — this one is special: it only shows up when it has **power** (12V). Plug it
  into the Mac with the wheel connected to a bench harness or powered in the car. If it's
  not powered, the tool will correctly report "no change detected."

## What it's doing (nothing scary)

For each device it takes a snapshot of the Mac's USB before and after you plug it in,
compares them, and records the device's ID and type. Everything it saves goes into an
`out/` folder next to this file. You can open `out/<device>-.../SUMMARY.txt` to see the
plain-English result yourself.

To delete everything it captured: `make clean`.
