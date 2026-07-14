@echo off
title marshal - trace how RS3 opens the SW4
REM Double-click this file. It records (with Process Monitor) how RaceStudio 3
REM opens the SW4 when it connects, then makes a .zip on your Desktop.
REM Process Monitor needs administrator rights, so it will ask you to click Yes.

REM --- self-elevate to administrator (Process Monitor requires it) ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Asking Windows for administrator access - please click "Yes" on the popup...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

REM --- remember this folder so the script can find a Procmon.exe you dropped here ---
set "MARSHAL_SRC=%~dp0"

REM --- copy the script to a LOCAL temp path so it runs even when this folder ---
REM --- lives on a Parallels shared drive (a \\Mac\... network path) ------------
copy /y "%~dp0trace-open.ps1" "%TEMP%\marshal-aim-open-trace.ps1" >nul
if errorlevel 1 (
  echo.
  echo Could not read trace-open.ps1 next to this file.
  echo Please copy the whole aim-open-trace folder onto your Windows Desktop,
  echo then double-click this file again from there.
  echo.
  pause
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\marshal-aim-open-trace.ps1"
del "%TEMP%\marshal-aim-open-trace.ps1" >nul 2>&1
