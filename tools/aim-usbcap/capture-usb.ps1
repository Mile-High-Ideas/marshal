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
# Requires USBPcap (installed once via the Wireshark installer). This script
# finds the USB bus the SW4 is on, captures to a .pcapng while you do the
# read/write in RaceStudio 3, then zips it to your Desktop.
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
# 3. List the USBPcap buses and find the one the SW4 is on
#    USBPcapCMD with no args prints a tree of buses + devices, then waits for a
#    selection. We feed it EOF, give it a moment to print, then read the output.
# ---------------------------------------------------------------------------
Section "Finding the SW4's USB bus"
$listing = ""
try {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $cmd
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Close()          # EOF so it stops waiting for a selection
  Start-Sleep -Milliseconds 1200
  if (-not $p.HasExited) { $p.Kill() }
  $listing = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
} catch {
  $listing = ""
}
$listing | Out-File (Join-Path $out "usbpcap-buses.txt")

# Parse: track the current "N \\.\USBPcapN" header, flag the block that names AiM.
$hub = $null
$cur = $null
foreach ($ln in ($listing -split "`r?`n")) {
  if     ($ln -match '^\s*(\d+)\s+\\\\\.\\USBPcap\d+') { $cur = $matches[1] }
  elseif ($cur -and ($ln -match 'AIM' -or $ln -match 'VID_11CC')) { $hub = $cur; break }
}

if ($hub) {
  Write-Host ("    the SW4 looks like it is on bus " + $hub) -ForegroundColor Green
  Write-Host ""
  Write-Host "    Full bus list (saved to usbpcap-buses.txt):"
  Write-Host $listing
  $ans = Read-Host ("Press Enter to use bus " + $hub + ", or type a different bus number")
  if ($ans.Trim() -ne '') { $hub = $ans.Trim() }
} else {
  Write-Host "    Could not auto-detect the bus. Here is the list:" -ForegroundColor Yellow
  Write-Host $listing
  $hub = (Read-Host "Type the number next to the bus that lists 'AIM USB Driver'").Trim()
}

if ($hub -notmatch '^\d+$') { Fail "That was not a bus number. Run the check again." }
$ctrl = "\\.\USBPcap$hub"
$pcap = Join-Path $out "sw4-$stamp.pcapng"

# ---------------------------------------------------------------------------
# 4. Start capturing, prompt for the RaceStudio 3 read/write, then stop
# ---------------------------------------------------------------------------
Section ("Capturing " + $ctrl + " -> " + $pcap)
$proc = Start-Process -FilePath $cmd -ArgumentList @('-d', $ctrl, '-o', "`"$pcap`"") -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 800

if ($proc.HasExited) {
  Fail @"
The capture failed to start on $ctrl.
Open usbpcap-buses.txt, note the correct bus number, and run this again.
(USBPcap needs administrator rights - the .bat should have asked for them.)
"@
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  CAPTURING. Now, in RaceStudio 3 on this laptop:"           -ForegroundColor Green
Write-Host "    1. Connect to the SW4."                                   -ForegroundColor Green
Write-Host "    2. Do a config READ."                                     -ForegroundColor Green
Write-Host "    3. Do a small WRITE (change one setting, send it)."       -ForegroundColor Green
Write-Host ""                                                             -ForegroundColor Green
Write-Host "  Try not to type anything sensitive - this records the USB"  -ForegroundColor Green
Write-Host "  bus the wheel is on for the next few seconds."              -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Read-Host "When the read AND write are done, press Enter here to STOP"

Section "Stopping capture"
try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
Start-Sleep -Milliseconds 400

$size = 0
if (Test-Path $pcap) { $size = (Get-Item $pcap).Length }
Write-Host ("    captured file: " + $pcap + "  (" + $size + " bytes)")
if ($size -lt 200) {
  Write-Host "    WARNING: the capture looks empty. Did the read/write happen on the right bus?" -ForegroundColor Yellow
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
