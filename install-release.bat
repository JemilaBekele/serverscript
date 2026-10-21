@echo off
:: Installs a SmartDent release zip. Right-click > Run as administrator is not
:: enough here (it needs the zip path): open cmd as administrator and run
::     install-release.bat "C:\path\to\SmartDent-....zip"
net session >nul 2>&1
if errorlevel 1 (
  echo Open Command Prompt as administrator and run this again.
  pause
  exit /b 1
)
if "%~1"=="" (
  echo Usage: install-release.bat "C:\path\to\SmartDent-....zip"
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-release.ps1" %*
pause
