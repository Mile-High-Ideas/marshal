@echo off
REM marshal — AiM capture launcher
REM Right-click this file and choose "Run as administrator" for full driver info.
REM (It still works without admin, just with less driver detail.)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture.ps1"

echo.
echo Look for the marshal-aim-capture-*.zip file in this folder and send it to Brandon.
echo.
pause
