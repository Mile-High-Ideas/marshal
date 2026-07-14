#!/usr/bin/env bash
#
# marshal USB discovery kit — run on the macOS host.
#
# Captures a full picture of the Mac + Parallels environment and the identity of
# each device (VID/PID in hex, USB class, /dev node, bound driver) by snapshotting
# USB state before and after you plug the device in, then diffing.
#
# Everything it uses ships with macOS. No Homebrew, no jq, no Python required.

set -euo pipefail

# ---------------------------------------------------------------------------
# pretty output
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  C_HEAD=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'
  C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_HEAD=; C_OK=; C_WARN=; C_ERR=; C_DIM=; C_OFF=
fi

say()  { printf '\n%s==>%s %s\n' "$C_HEAD" "$C_OFF" "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n'  "$C_WARN" "$C_OFF" "$*"; }
err()  { printf '%s[x]%s %s\n'  "$C_ERR" "$C_OFF" "$*"; }

pause_for_enter() {
  printf '\n%s%s%s' "$C_HEAD" "$1" "$C_OFF"
  # shellcheck disable=SC2162
  read _ < /dev/tty || true
}

# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="$HERE/out"
STAMP="$(date +%Y%m%d-%H%M%S)"

# lines we grep out of ioreg to fingerprint each attached USB device
IOREG_ID_FILTER='"idVendor"|"idProduct"|"USB Product Name"|"USB Vendor Name"|"USB Serial Number"|"bDeviceClass"|"bDeviceSubClass"'

# hex_id <decimal> -> 0xXXXX
hex_id() { printf '0x%04x' "$1" 2>/dev/null || echo "$1"; }

# ---------------------------------------------------------------------------
# host / environment capture — as much as is useful, upfront
# ---------------------------------------------------------------------------

capture_host() {
  local dir="$1"
  {
    echo "# Host environment — $(date)"
    echo "hostname: $(hostname 2>/dev/null)"
    echo "uptime:   $(uptime 2>/dev/null)"

    echo; echo "## macOS"
    sw_vers 2>/dev/null

    echo; echo "## Architecture"
    echo "uname -m           : $(uname -m 2>/dev/null)"
    echo "arm64 capable      : $(sysctl -n hw.optional.arm64 2>/dev/null)"
    echo "byte order / model : $(sysctl -n hw.byteorder hw.model 2>/dev/null | tr '\n' ' ')"
    uname -a 2>/dev/null

    echo; echo "## Hardware (chip / cores / RAM)"
    system_profiler SPHardwareDataType 2>/dev/null
    echo "hw.memsize (bytes) : $(sysctl -n hw.memsize 2>/dev/null)"
    echo "hw.ncpu            : $(sysctl -n hw.ncpu 2>/dev/null)"
    echo "physical/logical   : $(sysctl -n hw.physicalcpu hw.logicalcpu 2>/dev/null | tr '\n' '/')"
    echo "cpu brand          : $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"

    echo; echo "## Memory pressure / VM"
    vm_stat 2>/dev/null | head -6

    echo; echo "## Disk"
    df -h / 2>/dev/null

    echo; echo "## Parallels Desktop"
    if [ -d "/Applications/Parallels Desktop.app" ]; then
      /usr/bin/defaults read "/Applications/Parallels Desktop.app/Contents/Info.plist" \
        CFBundleShortVersionString 2>/dev/null | sed 's/^/app version: /'
    else
      echo "app: not found in /Applications"
    fi
    if command -v prlctl >/dev/null 2>&1; then
      echo "prlctl: $(prlctl --version 2>/dev/null)"
      echo "-- VMs --";        prlctl list -a 2>/dev/null
      echo "-- VM configs --"; prlctl list -a -i 2>/dev/null
    else
      echo "prlctl: not on PATH (Parallels CLI unavailable)"
    fi

    echo; echo "## Network hardware ports"
    networksetup -listallhardwareports 2>/dev/null
    echo "-- interfaces (brief) --"
    ifconfig -a 2>/dev/null | grep -E '^[a-z0-9]+:|status:|ether |inet ' | head -60

    echo; echo "## Thunderbolt / PCI (for adapters & docks)"
    system_profiler SPThunderboltDataType 2>/dev/null | head -80

    echo; echo "## Full USB tree (system_profiler)"
    system_profiler SPUSBDataType 2>/dev/null
  } > "$dir/host.txt" 2>&1
}

# ---------------------------------------------------------------------------
# per-tag USB snapshot
# ---------------------------------------------------------------------------

snapshot() {
  local dir="$1" tag="$2"
  system_profiler SPUSBDataType > "$dir/usb-$tag.txt"   2>/dev/null || true
  ioreg -p IOUSB -w0 -l       > "$dir/ioreg-$tag.txt"   2>/dev/null || true
  ls /dev/cu.* /dev/tty.* 2>/dev/null | sort > "$dir/dev-$tag.txt" || true
  # fingerprint each attached USB device's identity from ioreg — more reliable
  # than SPUSBDataType text, which can miss hub-attached or just-plugged devices
  ioreg -p IOUSB -w0 -l 2>/dev/null | grep -E "$IOREG_ID_FILTER" > "$dir/ids-$tag.txt" || true
}

# ---------------------------------------------------------------------------
# deep analysis of whatever appeared between before and after
# ---------------------------------------------------------------------------

analyze() {
  local dir="$1"
  local new_nodes new_ids verdict vid_dec pid_dec vid_hex pid_hex prod

  new_nodes="$(comm -13 "$dir/dev-before.txt" "$dir/dev-after.txt" 2>/dev/null || true)"
  # ids files are ordered ioreg output, so diff (not comm) surfaces the new device
  new_ids="$(diff "$dir/ids-before.txt" "$dir/ids-after.txt" 2>/dev/null | sed -n 's/^> //p' || true)"

  # pull the first new VID/PID/product for a hex-decoded headline
  vid_dec="$(printf '%s\n' "$new_ids" | sed -n 's/.*"idVendor" = \([0-9]*\).*/\1/p'  | head -1)"
  pid_dec="$(printf '%s\n' "$new_ids" | sed -n 's/.*"idProduct" = \([0-9]*\).*/\1/p' | head -1)"
  prod="$(printf '%s\n'    "$new_ids" | sed -n 's/.*"USB Product Name" = "\(.*\)".*/\1/p' | head -1)"
  [ -n "${vid_dec:-}" ] && vid_hex="$(hex_id "$vid_dec")" || vid_hex=""
  [ -n "${pid_dec:-}" ] && pid_hex="$(hex_id "$pid_dec")" || pid_hex=""

  # if we found a product name, capture its full IOService driver stack (what
  # kext claimed it — the definitive driver-model answer on the mac side)
  if [ -n "${prod:-}" ]; then
    ioreg -p IOService -w0 -l -n "$prod" > "$dir/driver-stack.txt" 2>/dev/null || true
  fi

  {
    echo "# Discovery summary"
    echo "device label : $(basename "$dir")"
    echo "captured     : $(date)"
    echo
    echo "## Identity"
    echo "product      : ${prod:-（none detected by name）}"
    echo "vendor  id   : ${vid_hex:-?} (${vid_dec:-?} dec)"
    echo "product id   : ${pid_hex:-?} (${pid_dec:-?} dec)"
    echo
    echo "## New serial /dev nodes after plug-in"
    if [ -n "$new_nodes" ]; then echo "$new_nodes"; else echo "(none)"; fi
    echo
    echo "## New USB identity lines (ioreg)"
    if [ -n "$new_ids" ]; then echo "$new_ids"; else echo "(none detected)"; fi
    echo
    echo "## Verdict hint"
  } > "$dir/SUMMARY.txt"

  if printf '%s' "$new_nodes" | grep -q 'usbmodem'; then
    verdict="USB-CDC (usbmodem node) -> BEST CASE. Windows-on-ARM gives this an inbox COM port (usbser.sys, ARM64). Zero bridge, zero cost."
  elif printf '%s' "$new_nodes" | grep -q 'usbserial'; then
    verdict="USB-serial (usbserial node) -> likely FTDI or CP210x. Vendor ships ARM64 drivers -> COM port. Zero bridge."
  elif [ -n "$new_ids" ]; then
    verdict="New USB device (${prod:-unknown}, ${vid_hex:-?}:${pid_hex:-?}) but NO serial node -> custom vendor class. Needs a marshald plugin (or a supported adapter). Send the bundle."
  else
    verdict="NO change detected. Likely causes: (1) device needs external power to enumerate — the AiM SW4 needs 12V; (2) try a different cable/port; (3) not a USB device."
  fi
  echo "$verdict" >> "$dir/SUMMARY.txt"

  say "Verdict"
  [ -n "${prod:-}" ] && info "device : ${prod} (${vid_hex:-?}:${pid_hex:-?})"
  printf '    %s\n' "$verdict"
  echo
  info "Full summary: $dir/SUMMARY.txt"
}

# ---------------------------------------------------------------------------
# per-device extra probes
# ---------------------------------------------------------------------------

device_extras() {
  local dir="$1" name="$2"
  case "$name" in
    ethernet-adapter)
      # for the Life Racing raw-L2 path we care about the adapter chipset and
      # the interface macOS assigned it (name, MAC, MTU, link state)
      {
        echo "# Ethernet adapter detail — $(date)"
        echo "## hardware ports"; networksetup -listallhardwareports 2>/dev/null
        echo; echo "## all interfaces"; ifconfig -a 2>/dev/null
        echo; echo "## en* link status"
        for i in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep '^en'); do
          echo "-- $i --"; ifconfig "$i" 2>/dev/null | grep -E 'ether|status|media|mtu'
        done
      } > "$dir/ethernet-detail.txt" 2>&1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# literal, device-specific plug-in instructions
# ---------------------------------------------------------------------------

plug_hint() {
  case "$1" in
    ecumaster)
      info "Plug the ECUMaster USB-to-CAN cable's USB plug into THIS Mac."
      info "You do NOT need the car, the PMU, or any CAN wiring — the cable powers itself over USB." ;;
    aim-sw4)
      warn "The AiM SW4 only shows up when it has 12V POWER."
      info "Connect the SW4 to the CAR and turn the ignition/accessory ON (or use a 12V bench harness),"
      info "THEN plug the SW4's USB plug into THIS Mac." ;;
    ethernet-adapter)
      info "Plug your USB-to-Ethernet adapter into THIS Mac."
      info "You do NOT need the ECU or a network cable connected for this step." ;;
    *)
      info "Plug the device into THIS Mac (make sure it has power if it needs it)." ;;
  esac
}

# ---------------------------------------------------------------------------
# flows
# ---------------------------------------------------------------------------

do_scan() {
  local name="$1"
  local dir="$OUT_ROOT/${name}-${STAMP}"
  mkdir -p "$dir"

  say "Scanning device: ${name}"
  info "Results will be saved to: ${dir#"$HERE"/}"
  say "Capturing full host + environment profile (this takes a few seconds)"
  capture_host "$dir"
  ok "Host profile captured."

  warn "Make sure the device is UNPLUGGED right now."
  pause_for_enter "Press Enter when it is unplugged... "
  snapshot "$dir" before
  ok "Baseline captured (device unplugged)."

  say "Now PLUG IN the device."
  plug_hint "$name"
  pause_for_enter "Wait about 5 seconds after plugging in, then press Return... "
  snapshot "$dir" after
  device_extras "$dir" "$name"
  ok "Post-plug state captured."

  analyze "$dir"
}

do_host() {
  local dir="$OUT_ROOT/host-${STAMP}"
  mkdir -p "$dir"
  say "Capturing full host + environment profile"
  capture_host "$dir"
  ok "Saved: ${dir#"$HERE"/}/host.txt"
}

do_bundle() {
  if [ ! -d "$OUT_ROOT" ]; then
    err "Nothing to bundle — run a scan first."
    exit 1
  fi
  local archive="$HERE/marshal-discovery-${STAMP}.tar.gz"
  ( cd "$HERE" && tar -czf "$archive" "$(basename "$OUT_ROOT")" )
  say "Bundle ready"
  ok "$archive"
  info "Send that single file back to Brandon."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

case "${1:-}" in
  --bundle)     do_bundle ;;
  --host-only)  do_host ;;
  "" )          err "No device name given. Try: make ecumaster | make aim | make ethernet"; exit 2 ;;
  * )           do_scan "$1" ;;
esac
