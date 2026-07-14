# Step 2 — Find the ECUMaster USB-to-CAN cable

> ✅ **Already confirmed** on 2026-07-13 (it's a standard USB serial device — great news). You
> only need to redo this step if asked.

**Goal:** identify how the ECUMaster USB-to-CAN cable talks to the Mac.

## What to connect

- Plug the **ECUMaster USB-to-CAN cable's USB plug into the Mac.**
- You do **NOT** need the car, the PMU, or any CAN wiring for this — **the cable powers itself
  over USB.**

## The easy way (no typing)

1. Open the `usb-discovery` folder in **Finder**.
2. **Double-click `2. Find ECUMaster Cable.command`.** The **Terminal app opens by itself.**
   - **First time only:** if macOS says *"cannot verify the developer,"* **right-click** the
     file → **Open** → **Open**. Once only.
3. Follow the two prompts in the window:
   - When it asks, make sure the cable is **unplugged**, then press **Return**.
   - Then **plug the cable into the Mac**, wait ~5 seconds, and press **Return**.
4. It prints a **verdict** and says the step is done. Press **Return** to close.

## If double-click doesn't work

Open the **Terminal** app and run:

```bash
cd ~/Downloads/marshal-main/tools/usb-discovery
make ecumaster
```

## What to send

Nothing yet — it's collected in **[Step 5 — Make the bundle](bundle.md)**.
