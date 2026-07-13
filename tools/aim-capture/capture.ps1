#requires -Version 5
#
# marshal — AiM SW4 / RaceStudio 3 Windows capture
#
# Run this INSIDE Windows (the Parallels guest, or any Windows PC that has
# RaceStudio 3 installed). It records how the SW4 enumerates and — most
# importantly — what DRIVER MODEL AiM uses, which decides whether marshal can
# bridge the SW4 as a simple COM port or has to reverse-engineer raw USB.
#
# It does NOT need the connection to actually work. Even a failed connect tells
# us the driver model and the exact error code.
#
# Best run "as administrator" (for full driver export), but it degrades
# gracefully without it.

$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out   = Join-Path $PSScriptRoot "out\aim-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Section($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

Section "Saving results to $out"

# ---------------------------------------------------------------------------
# 1. System + architecture (confirms Windows-on-ARM)
# ---------------------------------------------------------------------------
Section "System / architecture"
$sys = "$out\system.txt"
"# System — $(Get-Date)"                              | Out-File $sys
"PROCESSOR_ARCHITECTURE = $env:PROCESSOR_ARCHITECTURE"| Out-File $sys -Append
"PROCESSOR_ARCHITEW6432 = $env:PROCESSOR_ARCHITEW6432"| Out-File $sys -Append
Get-ComputerInfo -Property OsName,OsVersion,OsArchitecture,CsSystemType,WindowsProductName 2>$null |
  Format-List | Out-File $sys -Append

# ---------------------------------------------------------------------------
# 2. Every present USB / port / HID device, with status + problem code
# ---------------------------------------------------------------------------
Section "USB device inventory"
Get-PnpDevice -PresentOnly |
  Where-Object { $_.InstanceId -match 'USB' -or $_.Class -in 'USB','Ports','HIDClass','Net','WPD','Modem','SerialClass' } |
  Select-Object Status, Class, FriendlyName, InstanceId |
  Sort-Object Class, FriendlyName |
  Format-Table -AutoSize | Out-File "$out\usb-devices.txt" -Width 500
Get-PnpDevice -PresentOnly | Select-Object * | Export-Csv "$out\pnp-all.csv" -NoTypeInformation

# ---------------------------------------------------------------------------
# 3. The AiM device itself — the decisive capture
#    - Service name reveals the driver model:
#        usbser  -> USB-CDC  (marshal: simple COM bridge, best case)
#        FTDIBUS -> FTDI     (marshal: simple COM bridge)
#        WinUSB  -> WinUSB   (marshal: libusb bridge, medium)
#        <custom> -> AiM's own .sys (marshal: reverse-engineer raw USB, hard)
#    - ConfigManagerErrorCode reveals WHY it fails:
#        28 -> no driver ; 39 -> driver won't load ; 52 -> unsigned/ARM-incompatible
# ---------------------------------------------------------------------------
Section "AiM / SW4 device detail (the important part)"
$aimFile = "$out\aim-device.txt"
"# AiM / SW4 device detail — $(Get-Date)" | Out-File $aimFile

$aim = Get-PnpDevice -PresentOnly | Where-Object {
  $_.FriendlyName -match 'AiM|SW4|Race ?Studio' -or $_.Manufacturer -match 'AiM'
}

if ($aim) {
  foreach ($d in $aim) {
    "===== $($d.FriendlyName) =====" | Out-File $aimFile -Append
    Get-PnpDeviceProperty -InstanceId $d.InstanceId |
      Select-Object KeyName, Data | Format-Table -AutoSize |
      Out-File $aimFile -Append -Width 500
  }
} else {
  @(
    "No device matched AiM/SW4/RaceStudio by NAME."
    "If the SW4 is plugged in AND POWERED (it needs 12V to enumerate — comms"
    "ground is tied to battery ground), look in usb-devices.txt for an"
    "'Unknown Device' or a device with a yellow-bang / Problem code, and note"
    "its InstanceId (that carries the USB VID/PID)."
  ) | Out-File $aimFile -Append
}

# CIM view adds ConfigManagerErrorCode + Service (driver model) explicitly
"`n# Win32_PnPEntity view (ConfigManagerErrorCode + Service = driver model)" | Out-File $aimFile -Append
Get-CimInstance Win32_PnPEntity |
  Where-Object { $_.Name -match 'AiM|SW4|Race ?Studio' -or $_.PNPDeviceID -match 'VID_' } |
  Where-Object { $_.Name -match 'AiM|SW4|Race ?Studio' -or $_.ConfigManagerErrorCode -ne 0 } |
  Select-Object Name, PNPDeviceID, Status, ConfigManagerErrorCode, Service, Manufacturer |
  Format-List | Out-File $aimFile -Append

# ---------------------------------------------------------------------------
# 4. Installed drivers
# ---------------------------------------------------------------------------
Section "Driver inventory (pnputil needs admin; driverquery does not)"
pnputil /enum-drivers      > "$out\pnputil-drivers.txt" 2>&1
driverquery /v /fo csv     > "$out\driverquery.csv"      2>&1

# ---------------------------------------------------------------------------
# 5. AiM .inf files — the driver model in plain text
# ---------------------------------------------------------------------------
Section "Locating AiM driver INF files"
$infList = "$out\aim-inf-matches.txt"
"# INF files referencing AiM / RaceStudio / SW4" | Out-File $infList
$hits = Select-String -Path "C:\Windows\INF\*.inf" -Pattern 'AiM|RaceStudio|Race Studio|SW4' -List 2>$null
if ($hits) {
  $hits | ForEach-Object { $_.Path } | Sort-Object -Unique | ForEach-Object {
    $_ | Out-File $infList -Append
    Copy-Item $_ $out -Force
  }
} else { "none found in C:\Windows\INF" | Out-File $infList -Append }

# ---------------------------------------------------------------------------
# 6. RaceStudio install — bundled driver folder
# ---------------------------------------------------------------------------
Section "Locating RaceStudio install + bundled drivers"
$rsFile = "$out\racestudio-install.txt"
"# RaceStudio install locations + bundled .inf/.cat" | Out-File $rsFile
$rsDirs = Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match 'Race|AiM' }
foreach ($dir in $rsDirs) {
  "install dir: $($dir.FullName)" | Out-File $rsFile -Append
  Get-ChildItem $dir.FullName -Recurse -Include *.inf,*.cat -ErrorAction SilentlyContinue | ForEach-Object {
    "  driver file: $($_.FullName)" | Out-File $rsFile -Append
    Copy-Item $_.FullName $out -Force
  }
}
if (-not $rsDirs) { "RaceStudio install not found under Program Files." | Out-File $rsFile -Append }

# ---------------------------------------------------------------------------
# 7. Bundle
# ---------------------------------------------------------------------------
Section "Bundling"
$zip = Join-Path $PSScriptRoot "marshal-aim-capture-$stamp.zip"
Compress-Archive -Path $out -DestinationPath $zip -Force
Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "Bundle: $zip"
Write-Host "Send that single .zip back to Brandon."
