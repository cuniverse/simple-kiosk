@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater\install-prerequisites.ps1" -PackageRoot "%~dp0"
if errorlevel 1 (
  echo.
  echo Prerequisite installation failed.
  pause
  exit /b 1
)
echo.
echo Prerequisites are ready.
pause
