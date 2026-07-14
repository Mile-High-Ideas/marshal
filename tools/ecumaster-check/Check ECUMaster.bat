@echo off
title marshal - ECUMaster COM check
REM Double-click this file. It checks that the ECUMaster USB2CAN cable shows up
REM as a COM port in Windows, tells you which COM number to use in PMU Client,
REM and makes a .zip on your Desktop to send. No typing, no administrator needed.

REM --- copy the script to a LOCAL temp path so it runs even when this folder ---
REM --- lives on a Parallels shared drive (a \\Mac\... network path) ------------
copy /y "%~dp0check.ps1" "%TEMP%\marshal-ecumaster-check.ps1" >nul
if errorlevel 1 (
  echo.
  echo Could not read check.ps1 next to this file.
  echo Please copy the whole ecumaster-check folder onto your Windows Desktop,
  echo then double-click this file again from there.
  echo.
  pause
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\marshal-ecumaster-check.ps1"
del "%TEMP%\marshal-ecumaster-check.ps1" >nul 2>&1

echo.
echo ============================================================
echo   Done. Read the message above for your COM number, then
echo   look on your DESKTOP for marshal-ecumaster-check-^<date^>.zip
echo   and send it to Brandon.
echo ============================================================
echo.
pause
