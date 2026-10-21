@echo off
:: Keep-alive loop for the backend API. Started by start-system.bat.
call "%~dp0config.bat"
set "LOG=%LOG_DIR%\backend.log"
:: The backend reads .env from the folder it starts in.
cd /d "%BACKEND_DIR%"
:: An explicit PORT wins over .env, so both scripts agree on the port.
set "PORT=%BACKEND_PORT%"

:loop
if exist "%STOP_FLAG%" goto :eof
:: Keep the log under about 10 MB.
for %%F in ("%LOG%") do if %%~zF GTR 10485760 move /y "%LOG%" "%LOG%.old" >nul
if exist "dist\server.js" goto run
echo [%date% %time%] dist\server.js missing - run "npm run build" in %BACKEND_DIR% >> "%LOG%"
goto wait

:: Plain lines, not a ( ) block: inside a block %time% and %errorlevel%
:: would be read once, before the server even starts.
:run
echo [%date% %time%] Backend starting on port %BACKEND_PORT% >> "%LOG%"
node dist\server.js >> "%LOG%" 2>&1
echo [%date% %time%] Backend stopped (exit code %errorlevel%) >> "%LOG%"

:wait
if exist "%STOP_FLAG%" goto :eof
:: Wait 10 s. (timeout.exe fails at once when there is no console window,
:: as under Task Scheduler; ping works everywhere.)
ping -n 11 127.0.0.1 >nul
goto loop
