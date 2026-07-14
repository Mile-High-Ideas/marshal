@echo off
title marshal - AiM SW4 USB traffic capture
REM Double-click this file. It records the USB conversation between RaceStudio 3
REM and the SW4 while you do a config read/write, then makes a .zip on your
REM Desktop. USBPcap needs administrator rights, so it will ask you to click Yes.

REM --- self-elevate to administrator (USBPcap requires it) ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Asking Windows for administrator access - please click "Yes" on the popup...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

REM --- copy the script to a LOCAL temp path so it runs even when this folder ---
REM --- lives on a Parallels shared drive (a \\Mac\... network path) ------------
copy /y "%~dp0capture-usb.ps1" "%TEMP%\marshal-aim-usbcap.ps1" >nul
if errorlevel 1 (
  echo.
  echo Could not read capture-usb.ps1 next to this file.
  echo Please copy the whole aim-usbcap folder onto your Windows Desktop,
  echo then double-click this file again from there.
  echo.
  pause
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\marshal-aim-usbcap.ps1"
del "%TEMP%\marshal-aim-usbcap.ps1" >nul 2>&1
