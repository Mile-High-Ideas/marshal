# Step 3 — Find the AiM SW4

**Goal:** identify how the SW4 steering wheel talks to the Mac. This is the most important
device to get data on.

## ⚡ Read this first — the SW4 needs power

The SW4 **only shows up when it has 12V power.** Plugging just its USB into the Mac will show
**nothing**. So:

- Have the SW4 **connected to the car and turn the ignition / accessory ON** (so the wheel
  powers up), **or** power it from a **12V bench harness**.
- **Then** plug the SW4's **USB plug into the Mac.**

## The easy way (no typing)

1. Open the `usb-discovery` folder in **Finder**.
2. **Double-click `3. Find AiM SW4.command`.** The **Terminal app opens by itself.**
   - **First time only:** if macOS says *"cannot verify the developer,"* **right-click** the
     file → **Open** → **Open**. Once only.
3. Follow the two prompts:
   - Make sure the SW4's USB is **unplugged from the Mac**, press **Return**.
   - **Power the wheel** (ignition on / bench 12V), **plug its USB into the Mac**, wait ~5
     seconds, press **Return**.
4. Read the verdict, press **Return** to close.

If the verdict says *"NO change detected,"* the wheel almost certainly wasn't powered — power it
up and run the step again.

## If double-click doesn't work

Open the **Terminal** app and run:

```bash
cd ~/Downloads/marshal-main/tools/usb-discovery
make aim
```

## There is also a Windows step for the SW4

To fully crack the SW4 we also need info from **RaceStudio 3 on Windows** — that's a separate
kit: **`tools/aim-capture/`** (see its own README). Do that one when you can; this Mac step and
that Windows step together give us the complete picture.

## What to send

Collected in **[Step 5 — Make the bundle](bundle.md)**.
