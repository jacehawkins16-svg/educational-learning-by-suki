@echo off
setlocal
cd /d "%~dp0"
echo Starting local website server...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LocalSiteServer.ps1"
if errorlevel 1 (
  echo.
  echo The local server could not start. Make sure Windows PowerShell is available.
  pause
)