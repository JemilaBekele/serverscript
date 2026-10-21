@echo off
:: Registers the start-up and daily backup tasks. Right-click > Run as administrator.
net session >nul 2>&1
if errorlevel 1 (
  echo Please right-click install-tasks.bat and choose "Run as administrator".
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-tasks.ps1" %*
pause
