@echo off
:: Builds a release zip for clinic servers (supplier's PC only). See make-release.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make-release.ps1" %*
pause
