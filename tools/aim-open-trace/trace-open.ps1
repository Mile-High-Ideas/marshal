#requires -Version 5
#
# marshal - trace how RaceStudio 3 opens the AiM SW4 (Windows, Process Monitor)
#
# Run this on the standalone x64 laptop where RaceStudio 3 can CONNECT to the
# SW4. It records (with Process Monitor) exactly how RS3 opens the wheel - the
# CreateFile path/handle it uses - which is the fact the guest-side forwarder
# must impersonate. Then it drops a .zip on the Desktop to send to Brandon.
#
# NOTE: this file is intentionally plain ASCII. Windows PowerShell 5.1 misreads
# non-ASCII characters (em-dashes, smart quotes) and fails to parse. Keep it ASCII.

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$root = Join-Path $env:USERPROFILE "marshal-aim-open-trace"
$out  = Join-Path $root "trace-$stamp"
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
Unzip Procmon.exe NEXT TO this file (in the aim-open-trace folder), then
double-click "Trace SW4 Open.bat" again.
"@
  }
}
Write-Host ("    using: " + $procmon)

# ---------------------------------------------------------------------------
# 2. Nudge if the wheel isn't present (RS3 can't open what isn't plugged in)
# ---------------------------------------------------------------------------
$sw4 = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
  Where-Object { $_.InstanceId -match 'VID_11CC&PID_0110' }
if (-not $sw4) {
  Write-Host "    NOTE: the SW4 (VID_11CC/PID_0110) is not detected." -ForegroundColor Yellow
  Write-Host "          Power it (12V) and plug in its USB before connecting in RS3." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 3. Start Process Monitor logging to a backing file (headless)
# ---------------------------------------------------------------------------
$pml = Join-Path $out "procmon-rs3-open.pml"
Section "Starting Process Monitor (logging in the background)"
Start-Process -FilePath $procmon -ArgumentList @('/AcceptEula', '/Quiet', '/Minimized', '/BackingFile', "`"$pml`"")
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  LOGGING. Now, on this laptop:"                              -ForegroundColor Green
Write-Host "    1. Open RaceStudio 3."                                    -ForegroundColor Green
Write-Host "    2. CONNECT to the SW4 (a config READ is enough)."         -ForegroundColor Green
Write-Host ""                                                             -ForegroundColor Green
Write-Host "  Keep it short - just the connect. Do not type any"          -ForegroundColor Green
Write-Host "  passwords while it is logging."                             -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Read-Host "When RS3 has connected to the wheel, press Enter here to STOP"

# ---------------------------------------------------------------------------
# 4. Stop Process Monitor
# ---------------------------------------------------------------------------
Section "Stopping Process Monitor"
Start-Process -FilePath $procmon -ArgumentList @('/Terminate') -Wait
Start-Sleep -Milliseconds 800

$sz = 0
if (Test-Path $pml) { $sz = (Get-Item $pml).Length }
Write-Host ("    log size: " + $sz + " bytes")
if ($sz -lt 100000) {
  Write-Host "    WARNING: the log looks small - did RS3 actually connect to the wheel?" -ForegroundColor Yellow
}

$note = @"
marshal - AiM SW4 open trace

This bundle is a Process Monitor log (procmon-rs3-open.pml) recorded while
RaceStudio 3 connected to the AiM SW4 on this x64 PC.

What it is for: find the CreateFile path RS3 uses to OPEN the wheel
(e.g. \\?\HID#VID_11CC&PID_0110#... or a \\.\... device name / interface GUID).
That path is what the guest-side forwarder must present.

To read it: open the .pml in Process Monitor, then Filter ->
  Process Name is RaceStudio3.exe   (Include)
  Operation is CreateFile           (Include)
and look at the first successful device opens.
"@
$note | Out-File -Encoding ascii (Join-Path $out "READ-ME-first.txt")

# ---------------------------------------------------------------------------
# 5. Bundle onto the Desktop
# ---------------------------------------------------------------------------
Section "Bundling"
$desktop = [Environment]::GetFolderPath('Desktop')
$zip = Join-Path $desktop ("marshal-aim-open-trace-" + $stamp + ".zip")
Compress-Archive -Path $out -DestinationPath $zip -Force

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ("Bundle on your Desktop: " + $zip)
Write-Host "Send that single .zip file to Brandon."
Write-Host ""
Read-Host "Press Enter to close"
