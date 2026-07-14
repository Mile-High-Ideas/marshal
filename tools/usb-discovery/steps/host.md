# Step 1 — Capture Mac info

**Goal:** record what Mac you have and how Parallels is set up. No hardware needed for this
step.

## The easy way (no typing)

1. Open the `usb-discovery` folder in **Finder**.
2. **Double-click `1. Capture Mac Info.command`.**
   - The **Terminal app opens by itself** and runs everything — you don't type anything.
   - **First time only:** if macOS says *"cannot verify the developer"*, **right-click** (or
     Control-click) the file → choose **Open** → click **Open** in the dialog. You only do this
     once, then double-click works normally.
3. When it says *"This step is done,"* press **Return** to close the window.

## What it records

Your macOS version, the chip (e.g. Apple M-series), number of cores, **RAM**, disk space, the
**Parallels Desktop version and your virtual machines**, all network ports, and the full USB
device list. This is background info that helps set everything up correctly.

## If double-click doesn't work

Open the **Terminal** app (Applications → Utilities → Terminal), then type these two lines,
pressing Return after each:

```bash
cd ~/Downloads/marshal-main/tools/usb-discovery
make host
```

(Adjust the path if you put the folder somewhere other than Downloads.)

## What to send

Nothing yet — everything gets packaged together at the end in
**[Step 5 — Make the bundle](bundle.md)**.
