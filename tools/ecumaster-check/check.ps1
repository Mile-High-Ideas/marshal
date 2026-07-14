#requires -Version 5
#
# marshal - ECUMaster USB2CAN COM-port check (Windows guest)
#
# Run this INSIDE the Parallels Windows guest AFTER passing the ECUMASTER
# USB2CAN cable through to Windows. It confirms the cable shows up as a plain
# COM port bound to the inbox usbser driver (native ARM64) - the "no driver
# needed" bet - and tells you exactly which COM number to select in PMU Client.
#
# No administrator access needed. It does not change anything on the machine.
#
# NOTE: this file is intentionally plain ASCII. Windows PowerShell 5.1 misreads
# non-ASCII characters (em-dashes, smart quotes) and fails to parse. Keep it ASCII.

$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Write to a guaranteed-local folder (never a Parallels shared/UNC path).
$root = Join-Path $env:USERPROFILE "marshal-ecumaster-check"
$out  = Join-Path $root "ecumaster-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Section($msg) { Write-Host ("==> " + $msg) -ForegroundColor Cyan }

# STM32 Virtual COM Port = ECUMASTER USB2CAN (confirmed on the Mac: 0x0483/0x5740)
$VIDPID = 'VID_0483&PID_5740'

Section ("Saving results to " + $out)

# ---------------------------------------------------------------------------
# 1. System + architecture (confirms Windows-on-ARM)
# ---------------------------------------------------------------------------
Section "System / architecture"
$sys = Join-Path $out "system.txt"
("# System - " + (Get-Date))                               | Out-File $sys
("PROCESSOR_ARCHITECTURE = " + $env:PROCESSOR_ARCHITECTURE) | Out-File $sys -Append
Get-ComputerInfo -Property OsName,OsVersion,OsArchitecture,CsSystemType 2>$null |
  Format-List | Out-File $sys -Append

# ---------------------------------------------------------------------------
# 2. Every present COM / Ports / USB device
# ---------------------------------------------------------------------------
Section "Port + USB inventory"
Get-PnpDevice -PresentOnly |
  Where-Object { $_.Class -in 'Ports','USB','USBDevice' -or $_.InstanceId -match 'USB' } |
  Select-Object Status, Class, FriendlyName, InstanceId |
  Sort-Object Class, FriendlyName |
  Format-Table -AutoSize | Out-File (Join-Path $out "ports-devices.txt") -Width 500

# ---------------------------------------------------------------------------
# 3. The ECUMaster device itself - the decisive check
#    Service name reveals the driver model:
#      usbser  -> USB-CDC, inbox ARM64 COM port (the zero-bridge case we want)
#      <other> -> something else claimed it; send the bundle so Brandon can see
# ---------------------------------------------------------------------------
Section "ECUMaster device detail"
$devFile = Join-Path $out "ecumaster-device.txt"
("# ECUMaster USB2CAN detail - " + (Get-Date)) | Out-File $devFile

$all = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match $VIDPID }
$portsDev = $all | Where-Object { $_.Class -eq 'Ports' } | Select-Object -First 1

$com = $null
$service = $null
$statusOk = $false

if ($all) {
  foreach ($d in $all) {
    ("===== " + $d.Class + " : " + $d.FriendlyName + " =====") | Out-File $devFile -Append
    ("  Status     : " + $d.Status)     | Out-File $devFile -Append
    ("  InstanceId : " + $d.InstanceId) | Out-File $devFile -Append
  }

  ("`n# Win32_PnPEntity view (Service = driver model)") | Out-File $devFile -Append
  Get-CimInstance Win32_PnPEntity |
    Where-Object { $_.PNPDeviceID -match $VIDPID } |
    Select-Object Name, PNPDeviceID, Status, ConfigManagerErrorCode, Service |
    Format-List | Out-File $devFile -Append

  if ($portsDev) {
    $service  = (Get-CimInstance Win32_PnPEntity |
                 Where-Object { $_.PNPDeviceID -eq $portsDev.InstanceId }).Service
    $statusOk = ($portsDev.Status -eq 'OK')

    # COM number from the registry PortName (most reliable), fallback to name
    $pnKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $portsDev.InstanceId + "\Device Parameters"
    $com = (Get-ItemProperty -Path $pnKey -Name PortName -ErrorAction SilentlyContinue).PortName
    if (-not $com -and $portsDev.FriendlyName -match '\((COM\d+)\)') { $com = $matches[1] }
  }
} else {
  "No device with VID_0483 / PID_5740 is present in Windows." | Out-File $devFile -Append
}

# usbser driver evidence
("`n# usbser service (inbox ARM64 CDC driver)") | Out-File $devFile -Append
Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -eq 'usbser' } |
  Select-Object Name, State, Started, PathName | Format-List | Out-File $devFile -Append

# ---------------------------------------------------------------------------
# 4. Verdict
# ---------------------------------------------------------------------------
$lines = @()
if ($com -and $statusOk -and $service -eq 'usbser') {
  $lines += "PASS"
  $lines += ("The ECUMaster USB2CAN is " + $com + " via the inbox usbser driver (native ARM64).")
  $lines += "No third-party driver was needed - this is the zero-bridge case."
  $lines += ""
  $lines += ("NEXT: open PMU Client, select " + $com + ", and do a config READ (and a")
  $lines += "small WRITE if you can). The PMU16 must be powered and wired to the"
  $lines += "cable's CAN side for the read/write to actually talk to it."
} elseif ($portsDev) {
  $lines += "PARTIAL - look closer"
  $lines += "Found the cable as a port, but not the clean usbser case:"
  $lines += ("  COM     : " + $com)
  $lines += ("  Driver  : " + $service + "   (expected: usbser)")
  $lines += ("  Status  : " + $portsDev.Status)
  $lines += "Send the .zip to Brandon - the detail is in ecumaster-device.txt."
} elseif ($all) {
  $lines += "PRESENT BUT NO COM PORT"
  $lines += "The cable is in Windows but did not create a COM port. Send the .zip to Brandon."
} else {
  $lines += "NOT FOUND"
  $lines += "The ECUMaster USB2CAN is not connected to Windows yet."
  $lines += "On the Mac menu bar: Devices > USB & Bluetooth > click ECUMASTER USB2CAN"
  $lines += "(or STMicroelectronics Virtual COM Port) so it is connected to Windows,"
  $lines += "then double-click this check again."
}

$verdict = Join-Path $out "verdict.txt"
$lines | Out-File $verdict
("`n# Verdict") | Out-File $devFile -Append
$lines | Out-File $devFile -Append

# ---------------------------------------------------------------------------
# 5. Bundle onto the Desktop
# ---------------------------------------------------------------------------
Section "Bundling"
$desktop = [Environment]::GetFolderPath('Desktop')
$zip = Join-Path $desktop ("marshal-ecumaster-check-" + $stamp + ".zip")
Compress-Archive -Path $out -DestinationPath $zip -Force

# ---------------------------------------------------------------------------
# 6. Show the verdict big on screen (the COM number is what Shane needs)
# ---------------------------------------------------------------------------
$color = if ($lines[0] -eq 'PASS') { 'Green' } else { 'Yellow' }
Write-Host ""
Write-Host "============================================================"
foreach ($l in $lines) { Write-Host ("  " + $l) -ForegroundColor $color }
Write-Host "============================================================"
Write-Host ""
Write-Host ("Bundle on your Desktop: " + $zip) -ForegroundColor Green
Write-Host "Send that single .zip file to Brandon."
