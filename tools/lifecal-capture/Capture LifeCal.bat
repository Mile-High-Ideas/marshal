@echo off
title marshal - Life Racing / LifeCal capture
REM Double-click this file. It records how LifeCal talks to its Protocol Server
REM (Process Monitor + netstat) and the raw frames (a built-in packet trace)
REM while you connect and do a read/write, then makes a .zip on your Desktop.
REM This needs administrator rights, so it will ask you to click Yes.

REM --- self-elevate to administrator (Process Monitor + packet trace need it) ---
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
copy /y "%~dp0capture-lifecal.ps1" "%TEMP%\marshal-lifecal-capture.ps1" >nul
if errorlevel 1 (
  echo.
  echo Could not read capture-lifecal.ps1 next to this file.
  echo Please copy the whole lifecal-capture folder onto your Windows Desktop,
  echo then double-click this file again from there.
  echo.
  pause
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\marshal-lifecal-capture.ps1"
del "%TEMP%\marshal-lifecal-capture.ps1" >nul 2>&1
