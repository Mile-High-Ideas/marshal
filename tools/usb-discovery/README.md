# USB discovery kit (for Shane)

This figures out **how each device talks to the Mac**, which tells us whether it can work on
your Apple-Silicon Mac in Parallels. It runs **on the Mac**, uses only what's already built into
macOS (nothing to install), and packages the results into one file to send back.

## How it works (30-second version)

Each step is a file you **double-click** in Finder. It **opens the Terminal app by itself** and
runs — you just follow the on-screen prompts (usually "unplug, press Return" then "plug in,
press Return"). You do not have to type anything.

> **First time you open one of these:** macOS may say *"cannot verify the developer."* If it
> does, **right-click** (or Control-click) the file → choose **Open** → click **Open**. You only
> do this once; after that, double-click works normally.

## Do the steps in this order

| # | Double-click this file | What it's for | Instructions |
|---|---|---|---|
| 1 | `1. Capture Mac Info.command` | Your Mac + Parallels info (no hardware needed) | [host.md](steps/host.md) |
| 2 | `2. Find ECUMaster Cable.command` | The ECUMaster USB-to-CAN cable ✅ *(already done)* | [ecumaster.md](steps/ecumaster.md) |
| 3 | `3. Find AiM SW4.command` | The AiM SW4 wheel — **must be powered (12V)** | [aim.md](steps/aim.md) |
| 4 | `4. Find Ethernet Adapter.command` | The USB-to-Ethernet adapter (Life Racing) | [ethernet.md](steps/ethernet.md) |
| 5 | `5. Make Bundle to Send.command` | Packages everything into one file to send | [bundle.md](steps/bundle.md) |

Run the steps for whatever you have on hand (at least Step 1), then **Step 5** and send Brandon
the one `marshal-discovery-<date>.tar.gz` file it makes.

Click any step above for full, literal instructions — including what to physically connect
(e.g. the SW4 must be **powered / connected to the car**).

## Prefer the terminal?

There's a `Makefile` too. In Terminal:

```bash
cd ~/Downloads/marshal-main/tools/usb-discovery
make host        # step 1
make ecumaster   # step 2
make aim         # step 3
make ethernet    # step 4
make bundle      # step 5
make help        # list everything
```

## Notes

- **Nothing personal** is collected — just macOS/hardware info and USB device identities. Open
  any `out/.../SUMMARY.txt` to see results yourself.
- To start over: `make clean` (or delete the `out/` folder).
- There's a separate **Windows** kit for the AiM SW4 in `../aim-capture/` — do that one too when
  you can; the Mac step and the Windows step together give the full picture.
