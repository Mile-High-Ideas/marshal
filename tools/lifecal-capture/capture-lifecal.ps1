#requires -Version 5
#
# marshal - Life Racing / LifeCal capture (Windows)
#
# Run this on the standalone x64 laptop where LifeCal can CONNECT to the ECU.
# It records the two things that unblock the Life Racing plugin:
#   1. HOW LifeCal reaches its "Ethernet Protocol Server" (Process Monitor +
#      netstat) - the decisive unknown: a redirectable localhost socket, or
#      in-process via the Rawether driver?
#   2. The raw layer-2 frames (a built-in Windows packet trace, best effort).
# Then it drops a .zip on the Desktop to send to Brandon.
#
# NOTE: this file is intentionally plain ASCII. Windows PowerShell 5.1 misreads
# non-ASCII characters (em-dashes, smart quotes) and fails to parse. Keep it ASCII.

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$root = Join-Path $env:USERPROFILE "marshal-lifecal-capture"
$out  = Join-Path $root "lifecal-$stamp"
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
# 1. Find Process Monitor, or download it (single .exe, no install)
# ---------------------------------------------------------------------------
Section "Getting Process Monitor"
$procmon = $null
$cands = @(
  (Join-Path $env:MARSHAL_SRC 'Procmon.exe'),
  (Join-Path $env:MARSHAL_SRC 'Procmon64.exe'),
  (Join-Path $env:TEMP 'marshal-procmon.exe')
)
foreach ($c in $cands) { if ($c -and (Test-Path $c)) { $procmon = $c; break } }
if (-not $procmon) {
  $dst = Join-Path $env:TEMP 'marshal-procmon.exe'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://live.sysinternals.com/Procmon.exe' -OutFile $dst -UseBasicParsing
    $procmon = $dst
  } catch {
    Fail @"
Could not download Process Monitor automatically.

Get it here (a single .exe, no install):
  https://learn.microsoft.com/sysinternals/downloads/procmon
Unzip Procmon.exe NEXT TO this file (in the lifecal-capture folder), then
double-click "Capture LifeCal.bat" again.
"@
  }
}
Write-Host ("    using: " + $procmon)

# ---------------------------------------------------------------------------
# 2. Snapshot before: sockets, the Protocol Server process/service, drivers
# ---------------------------------------------------------------------------
Section "Recording current sockets and the Protocol Server identity"
cmd /c "netstat -ano -b" | Out-File -Encoding ascii (Join-Path $out "netstat-before.txt")

try {
  Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path } |
    Where-Object { $_.Name -match 'life|rawether|protocol|lfnt|syvecs' -or $_.Path -match 'Life *Racing|LifeCal|Rawether|Protocol' } |
    Select-Object Name, Id, Path | Format-Table -AutoSize | Out-String |
    Out-File -Encoding ascii (Join-Path $out "protocol-server-processes.txt")
} catch { }
try {
  Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'life|rawether|protocol|lfnt|syvecs' -or $_.PathName -match 'Life|Rawether|Protocol' } |
    Select-Object Name, DisplayName, State, StartMode, PathName | Format-List |
    Out-String | Out-File -Encoding ascii (Join-Path $out "protocol-server-services.txt")
} catch { }
try { cmd /c "driverquery /v" | Out-File -Encoding ascii (Join-Path $out "drivers.txt") } catch { }

# ---------------------------------------------------------------------------
# 3. Start Process Monitor + a built-in packet trace (best effort)
# ---------------------------------------------------------------------------
$pml = Join-Path $out "procmon-lifecal.pml"
$etl = Join-Path $out "frames.etl"
Section "Starting Process Monitor + packet trace"
Start-Process -FilePath $procmon -ArgumentList @('/AcceptEula', '/Quiet', '/Minimized', '/BackingFile', "`"$pml`"")

$netshOK = $false
try {
  cmd /c "netsh trace start capture=yes report=no overwrite=yes maxSize=512 tracefile=`"$etl`"" 2>&1 |
    Out-File -Encoding ascii (Join-Path $out "netsh-start.txt")
  if ($LASTEXITCODE -eq 0) { $netshOK = $true }
} catch { }
if ($netshOK) {
  Write-Host "    packet trace: ON (frames.etl - Brandon converts it to .pcapng)"
} else {
  Write-Host "    packet trace unavailable - Process Monitor + netstat still capture the key info." -ForegroundColor Yellow
}
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  LOGGING. Now, on this laptop:"                              -ForegroundColor Green
Write-Host "    1. Open LifeCal and CONNECT to the ECU."                  -ForegroundColor Green
Write-Host "    2. Do a config READ."                                     -ForegroundColor Green
Write-Host "    3. Do a small WRITE (change one setting and send it)."    -ForegroundColor Green
Write-Host ""                                                             -ForegroundColor Green
Write-Host "  Do not type any passwords while it is logging."             -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Read-Host "When the read AND write are done, press Enter here to STOP"

# ---------------------------------------------------------------------------
# 4. Stop everything and snapshot sockets again
# ---------------------------------------------------------------------------
Section "Stopping"
Start-Process -FilePath $procmon -ArgumentList @('/Terminate') -Wait
if ($netshOK) {
  Write-Host "    finishing the packet trace (this can take a minute)..."
  try { cmd /c "netsh trace stop" 2>&1 | Out-File -Encoding ascii (Join-Path $out "netsh-stop.txt") } catch { }
}
cmd /c "netstat -ano -b" | Out-File -Encoding ascii (Join-Path $out "netstat-during.txt")

$pmlSz = 0
if (Test-Path $pml) { $pmlSz = (Get-Item $pml).Length }
Write-Host ("    Process Monitor log: " + $pmlSz + " bytes")
if ($pmlSz -lt 100000) {
  Write-Host "    WARNING: the log looks small - did LifeCal actually connect / read / write?" -ForegroundColor Yellow
}

$note = @"
marshal - Life Racing / LifeCal capture

Contents:
  procmon-lifecal.pml            Process Monitor log of the LifeCal session
  netstat-before/during.txt      open sockets before and during the session
  frames.etl                     raw packet trace (convert to .pcapng with
                                 etl2pcapng, or open with the appropriate tool)
  protocol-server-*.txt          the LifeCal Protocol Server process/service/driver
  drivers.txt                    installed drivers (look for Rawether / LfNtSp)

The key question Brandon answers from this: does LifeCal reach its Protocol
Server over a 127.0.0.1 socket (redirectable) or in-process via DeviceIoControl
to the Rawether driver / a named pipe (in-process)? Read it in Process Monitor:
  Filter -> Process Name is (the LifeCal exe)  Include
  look for Operation: TCP/UDP Connect/Send/Receive to 127.0.0.1  (socket)
           vs  DeviceIoControl / named pipe / shared memory       (in-process)
"@
$note | Out-File -Encoding ascii (Join-Path $out "READ-ME-first.txt")

# ---------------------------------------------------------------------------
# 5. Bundle onto the Desktop
# ---------------------------------------------------------------------------
Section "Bundling"
$desktop = [Environment]::GetFolderPath('Desktop')
$zip = Join-Path $desktop ("marshal-lifecal-capture-" + $stamp + ".zip")
Compress-Archive -Path $out -DestinationPath $zip -Force

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ("Bundle on your Desktop: " + $zip)
Write-Host "Send that single .zip file to Brandon."
Write-Host ""
Read-Host "Press Enter to close"
