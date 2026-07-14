# Step 5 — Make the bundle to send

**Goal:** package all the results from the earlier steps into **one file** to send back.

Do this **after** you've run the steps you can (at least Step 1, plus whichever devices you
have on hand).

## The easy way (no typing)

1. Open the `usb-discovery` folder in **Finder**.
2. **Double-click `5. Make Bundle to Send.command`.** The **Terminal app opens by itself** and
   creates the file.
   - **First time only:** if macOS says *"cannot verify the developer,"* **right-click** the
     file → **Open** → **Open**. Once only.
3. A file named **`marshal-discovery-<date>.tar.gz`** appears in the `usb-discovery` folder.

## Send it

**Send that one `marshal-discovery-<date>.tar.gz` file to Brandon** — drag it into Messages or
attach it to an email. That's everything, in a single file.

## If double-click doesn't work

Open the **Terminal** app and run:

```bash
cd ~/Downloads/marshal-main/tools/usb-discovery
make bundle
```

## Nothing personal in it

It's just hardware/OS info and USB device identities. You can open the `out/` folder and read
any of the `SUMMARY.txt` files yourself before sending.
