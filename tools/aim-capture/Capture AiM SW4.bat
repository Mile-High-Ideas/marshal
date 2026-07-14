@echo off
title marshal - AiM SW4 capture
REM Double-click this file. It asks Windows for administrator access (click
REM "Yes"), collects the info, and makes a .zip for you to send to Brandon.
REM You do not need to type anything.

REM --- self-elevate to administrator so the driver details are complete ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Asking Windows for administrator access - please click "Yes" on the popup...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture.ps1"

echo.
echo ============================================================
echo   Done. A file named  marshal-aim-capture-^<date^>.zip
echo   is now in this folder. Send that ONE file to Brandon.
echo   (drag it into Messages or attach it to an email)
echo ============================================================
echo.
pause
