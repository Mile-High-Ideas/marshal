#requires -Version 5
#
# marshal - AiM SW4 USB traffic capture (Windows, USBPcap)
#
# Run this on the machine where RaceStudio 3 can actually CONNECT to the SW4
# (Shane's standalone x64 "old racing laptop" - NOT the Parallels guest, where
# the AiM x64 driver cannot load). It records the real USB conversation between
# RaceStudio 3 and the wheel during a config read/write, which is the one thing
# left that decides how marshal bridges the SW4.
#
# Requires USBPcap (installed once via the Wireshark installer). To avoid the
# fragile "pick a bus" menu, this captures EVERY USB bus at once for the few
# seconds of the read/write; Brandon filters to the wheel (VID 11CC) afterward.
#
# NOTE: this file is intentionally plain ASCII. Windows PowerShell 5.1 misreads
# non-ASCII characters (em-dashes, smart quotes) and fails to parse. Keep it ASCII.

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$root = Join-Path $env:USERPROFILE "marshal-aim-usbcap"
$out  = Join-Path $root "usbcap-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Section($msg) { Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Fail($msg) {
  Write-Host ""
  Write-Host $msg -ForegroundColor Yellow
  Write-Host ""
  Read-Host "Press Enter to close"
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Locate USBPcapCMD.exe (installed with Wireshark's USBPcap component)
# ---------------------------------------------------------------------------
Section "Looking for USBPcap"
$cmd = @(
  (Join-Path $env:ProgramFiles        "USBPcap\USBPcapCMD.exe"),
  (Join-Path ${env:ProgramFiles(x86)} "USBPcap\USBPcapCMD.exe")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $cmd) {
  Fail @"
USBPcap is not installed.

Install it once (it is a checkbox in the Wireshark installer):
  1. Download Wireshark:  https://www.wireshark.org/download.html
  2. Run the installer. On the components screen, make sure "USBPcap"
     is CHECKED.
  3. Reboot if it asks.
  4. Double-click "Capture SW4 Traffic.bat" again.
"@
}
Write-Host ("    found: " + $cmd)

# ---------------------------------------------------------------------------
# 2. Confirm the SW4 is plugged in and powered
# ---------------------------------------------------------------------------
Section "Checking the SW4 is connected"
$sw4 = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_11CC&PID_0110' }
if (-not $sw4) {
  Fail @"
The AiM SW4 (USB VID_11CC / PID_0110) is not present.

Power the wheel (it needs 12V - comms ground is tied to battery ground),
plug its USB into this laptop, then run this again.
"@
}
Write-Host ("    found: " + ($sw4 | Select-Object -First 1).FriendlyName)

# ---------------------------------------------------------------------------
# 3. Enumerate the USBPcap buses the reliable way (--extcap-interfaces prints
#    machine-readable lines; the interactive tree menu does NOT survive output
#    redirection, so we never use it). We capture every bus.
# ---------------------------------------------------------------------------
Section "Listing USBPcap buses"
$ifaces = @()
try {
  $raw = & $cmd --extcap-interfaces 2>&1 | Out-String
  $raw | Out-File (Join-Path $out "usbpcap-interfaces.txt")
  foreach ($m in [regex]::Matches($raw, 'value=([^}]+)')) { $ifaces += $m.Groups[1].Value.Trim() }
} catch { }
$ifaces = $ifaces | Where-Object { $_ -match 'USBPcap' } | Select-Object -Unique

if (-not $ifaces -or $ifaces.Count -eq 0) {
  Fail @"
Could not list any USBPcap buses. USBPcap may not have installed correctly.
Reinstall Wireshark with the USBPcap box CHECKED, reboot, then try again.
"@
}
Write-Host ("    buses: " + ($ifaces -join ', '))

# ---------------------------------------------------------------------------
# 4. Start one capture per bus, prompt for the RaceStudio 3 read/write, stop all
# ---------------------------------------------------------------------------
Section "Starting capture on all buses"
$procs = @()
$n = 0
foreach ($if in $ifaces) {
  $n++
  $f = Join-Path $out ("bus$n.pcapng")
  $procs += Start-Process -FilePath $cmd -ArgumentList @('-d', $if, '-o', "`"$f`"") -PassThru -WindowStyle Hidden
}
Start-Sleep -Milliseconds 900
if (-not ($procs | Where-Object { -not $_.HasExited })) {
  Fail @"
The captures did not start. USBPcap needs administrator rights - the .bat should
have asked for them (the title bar should say "Administrator"). Close this and
re-run "Capture SW4 Traffic.bat", clicking Yes on the popup.
"@
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  CAPTURING. Now, in RaceStudio 3 on this laptop:"           -ForegroundColor Green
Write-Host "    1. Connect to the SW4."                                   -ForegroundColor Green
Write-Host "    2. Do a config READ."                                     -ForegroundColor Green
Write-Host "    3. Do a small WRITE (change one setting, send it)."       -ForegroundColor Green
Write-Host ""                                                             -ForegroundColor Green
Write-Host "  This records ALL USB buses for these few seconds, so please" -ForegroundColor Green
Write-Host "  do not type any passwords until you press Enter below."      -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Read-Host "When the read AND write are done, press Enter here to STOP"

Section "Stopping capture"
foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { } }
Start-Sleep -Milliseconds 500

$total = 0
Get-ChildItem (Join-Path $out "*.pcapng") -ErrorAction SilentlyContinue | ForEach-Object { $total += $_.Length }
Write-Host ("    captured " + $total + " bytes across " + $ifaces.Count + " bus file(s)")
if ($total -lt 500) {
  Write-Host "    WARNING: the capture looks nearly empty - did the RS3 read/write actually run?" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 5. Bundle onto the Desktop
# ---------------------------------------------------------------------------
Section "Bundling"
$desktop = [Environment]::GetFolderPath('Desktop')
$zip = Join-Path $desktop ("marshal-aim-usbcap-" + $stamp + ".zip")
Compress-Archive -Path $out -DestinationPath $zip -Force

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ("Bundle on your Desktop: " + $zip)
Write-Host "Send that single .zip file to Brandon."
Write-Host ""
Read-Host "Press Enter to close"
