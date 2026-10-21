@echo off
:: ============================================================================
::  AFET Dental Care - start the backend and the frontend.
::  Each runs in its own keep-alive loop: if it stops or crashes it is
::  restarted after 10 seconds, until stop-system.bat is run.
::  Run hidden through RunServer.vbs (Task Scheduler) or double-click this.
:: ============================================================================
call "%~dp0config.bat"
if exist "%STOP_FLAG%" del "%STOP_FLAG%"

echo [%date% %time%] Starting AFET Dental Care >> "%LOG_DIR%\system.log"

:: Skip a part that is already running, so a second start does not clash.
netstat -ano | findstr /r /c:":%BACKEND_PORT% .*LISTENING" >nul
if errorlevel 1 (
  start "" /b cmd /c ""%~dp0run-backend.bat""
) else (
  echo [%date% %time%] Backend already running on port %BACKEND_PORT% >> "%LOG_DIR%\system.log"
)

netstat -ano | findstr /r /c:":%FRONTEND_PORT% .*LISTENING" >nul
if errorlevel 1 (
  start "" /b cmd /c ""%~dp0run-frontend.bat""
) else (
  echo [%date% %time%] Frontend already running on port %FRONTEND_PORT% >> "%LOG_DIR%\system.log"
)
