@echo off
:: ============================================================================
::  drlemlem - stop the backend and the frontend.
::  Run as Administrator if the system was started by Task Scheduler.
:: ============================================================================
call "%~dp0config.bat"
:: Tell the keep-alive loops not to restart, then stop the running servers.
echo stop> "%STOP_FLAG%"
echo [%date% %time%] Stopping drlemlem >> "%LOG_DIR%\system.log"

for %%P in (%BACKEND_PORT% %FRONTEND_PORT%) do (
  for /f "tokens=5" %%I in ('netstat -ano ^| findstr /r /c:":%%P .*LISTENING"') do (
    taskkill /PID %%I /T /F >nul 2>&1 && echo Stopped the server on port %%P
  )
)
echo drlemlem stopped.
