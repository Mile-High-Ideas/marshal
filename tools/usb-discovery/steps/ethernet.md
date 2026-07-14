# Step 4 — Find the USB-to-Ethernet adapter (Life Racing)

**Goal:** identify the USB-to-Ethernet adapter you use for Life Racing / LifeCal, and how macOS
sees it. This tells us whether it can carry the Life Racing connection later.

## What to connect

- Plug your **USB-to-Ethernet adapter into the Mac.**
- You do **NOT** need the ECU or an Ethernet cable connected for this step — just the adapter
  itself.

## The easy way (no typing)

1. Open the `usb-discovery` folder in **Finder**.
2. **Double-click `4. Find Ethernet Adapter.command`.** The **Terminal app opens by itself.**
   - **First time only:** if macOS says *"cannot verify the developer,"* **right-click** the
     file → **Open** → **Open**. Once only.
3. Follow the two prompts:
   - Make sure the adapter is **unplugged**, press **Return**.
   - **Plug the adapter into the Mac**, wait ~5 seconds, press **Return**.
4. Read the verdict, press **Return** to close.

## If double-click doesn't work

Open the **Terminal** app and run:

```bash
cd ~/Downloads/marshal-main/tools/usb-discovery
make ethernet
```

## What to send

Collected in **[Step 5 — Make the bundle](bundle.md)**.
