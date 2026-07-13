#!/usr/bin/env bash
#
# marshal USB discovery kit — run on the macOS host.
#
# Captures the identity of a USB device (VID/PID, class, /dev node, descriptor
# strings) by snapshotting the Mac's USB state before and after you plug the
# device in, then diffing. Also grabs host + Parallels environment info.
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
warn() { printf '%s[!]%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_ERR" "$C_OFF" "$*"; }

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

# ---------------------------------------------------------------------------
# capture helpers
# ---------------------------------------------------------------------------

# snapshot <dir> <tag> — record the full USB state under a tag (before/after).
snapshot() {
  local dir="$1" tag="$2"
  system_profiler SPUSBDataType > "$dir/usb-$tag.txt" 2>/dev/null || true
  ioreg -p IOUSB -w0 -l      > "$dir/ioreg-$tag.txt" 2>/dev/null || true
  # serial device nodes are the fastest tell of the USB class
  ls /dev/cu.* /dev/tty.* 2>/dev/null | sort > "$dir/dev-$tag.txt" || true
  # a stable fingerprint of every VID/PID currently attached
  grep -E 'Vendor ID:|Product ID:' "$dir/usb-$tag.txt" 2>/dev/null \
    | sort -u > "$dir/ids-$tag.txt" || true
}

capture_host() {
  local dir="$1"
  {
    echo "# Host environment — $(date)"
    echo
    echo "## macOS"
    sw_vers 2>/dev/null || true
    echo
    echo "## Architecture"
    echo "uname -m : $(uname -m)"
    uname -a 2>/dev/null || true
    echo
    echo "## Hardware"
    sysctl -n hw.model 2>/dev/null || true
    sysctl -n machdep.cpu.brand_string 2>/dev/null || true
    echo
    echo "## Parallels Desktop"
    if [ -d "/Applications/Parallels Desktop.app" ]; then
      /usr/bin/defaults read "/Applications/Parallels Desktop.app/Contents/Info.plist" \
        CFBundleShortVersionString 2>/dev/null | sed 's/^/version: /' || true
    else
      echo "not found in /Applications"
    fi
    command -v prlctl >/dev/null 2>&1 && { echo "prlctl:"; prlctl --version 2>/dev/null || true; }
    echo
    echo "## Network hardware ports (for the Life Racing Ethernet adapter)"
    networksetup -listallhardwareports 2>/dev/null || true
  } > "$dir/host.txt" 2>&1
}

# ---------------------------------------------------------------------------
# verdict
# ---------------------------------------------------------------------------

analyze() {
  local dir="$1"
  local new_nodes new_ids verdict

  new_nodes="$(comm -13 "$dir/dev-before.txt" "$dir/dev-after.txt" 2>/dev/null || true)"
  # new VID/PID lines that appeared after plugging in
  new_ids="$(comm -13 "$dir/ids-before.txt" "$dir/ids-after.txt" 2>/dev/null || true)"

  {
    echo "# Discovery summary"
    echo "device label : $(basename "$dir")"
    echo "captured     : $(date)"
    echo
    echo "## New serial /dev nodes after plug-in"
    if [ -n "$new_nodes" ]; then echo "$new_nodes"; else echo "(none)"; fi
    echo
    echo "## New USB Vendor/Product IDs after plug-in"
    if [ -n "$new_ids" ]; then echo "$new_ids"; else echo "(none detected)"; fi
    echo
    echo "## Verdict hint"
  } > "$dir/SUMMARY.txt"

  if printf '%s' "$new_nodes" | grep -q 'usbmodem'; then
    verdict="USB-CDC (usbmodem node) -> BEST CASE. Windows-on-ARM gives this an inbox COM port. Zero bridge, zero cost."
  elif printf '%s' "$new_nodes" | grep -q 'usbserial'; then
    verdict="USB-serial (usbserial node) -> likely FTDI or CP210x. Vendor ships ARM64 drivers -> COM port. Zero bridge."
  elif [ -n "$new_ids" ]; then
    verdict="New USB device but NO serial node -> custom vendor class. Needs a marshald plugin (or a supported adapter). Send the bundle."
  else
    verdict="NO change detected. Likely causes: (1) the device needs external power to enumerate — the AiM SW4 needs 12V bench/car power; (2) try a different cable/port; (3) it is not a USB device."
  fi

  echo "$verdict" >> "$dir/SUMMARY.txt"

  say "Verdict"
  printf '    %s\n' "$verdict"
  echo
  info "Full summary: $dir/SUMMARY.txt"
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
  capture_host "$dir"

  warn "Make sure the device is UNPLUGGED right now."
  pause_for_enter "Press Enter when it is unplugged... "
  snapshot "$dir" before
  ok "Baseline captured (device unplugged)."

  say "Now PLUG IN the device."
  info "AiM SW4: it must also be powered (12V bench harness or in the car) to appear."
  info "ECUMaster USB->CAN cable and USB->Ethernet adapters power themselves over USB."
  pause_for_enter "Wait ~5 seconds after plugging in, then press Enter... "
  snapshot "$dir" after
  ok "Post-plug state captured."

  analyze "$dir"
}

do_host() {
  local dir="$OUT_ROOT/host-${STAMP}"
  mkdir -p "$dir"
  say "Capturing host environment"
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
