@echo off
title marshal - AiM SW4 capture
REM Double-click this file. It asks Windows for administrator access (click
REM "Yes"), collects the info, and makes a .zip on your Desktop to send.
REM You do not need to type anything.

REM --- self-elevate to administrator so the driver details are complete ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Asking Windows for administrator access - please click "Yes" on the popup...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

REM --- copy the script to a LOCAL temp path so it runs even when this folder ---
REM --- lives on a Parallels shared drive (a \\Mac\... network path) ---------
copy /y "%~dp0capture.ps1" "%TEMP%\marshal-aim-capture.ps1" >nul
if errorlevel 1 (
  echo.
  echo Could not read capture.ps1 next to this file.
  echo Please copy the whole aim-capture folder onto your Windows Desktop,
  echo then double-click this file again from there.
  echo.
  pause
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\marshal-aim-capture.ps1"
del "%TEMP%\marshal-aim-capture.ps1" >nul 2>&1

echo.
echo ============================================================
echo   Done. Look on your DESKTOP for a file named
echo   marshal-aim-capture-^<date^>.zip  and send it to Brandon.
echo   (drag it into Messages or attach it to an email)
echo ============================================================
echo.
pause
