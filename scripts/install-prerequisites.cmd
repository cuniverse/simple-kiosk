@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater\install-prerequisites.ps1" -PackageRoot "%~dp0"
if errorlevel 1 (
  echo.
  echo Simple Kiosk prerequisite installation failed.
  pause
  exit /b 1
)
echo.
echo Simple Kiosk prerequisites are ready.
pause
