@echo off
:: Keep-alive loop for the frontend (standalone build). Started by start-system.bat.
call "%~dp0config.bat"
set "LOG=%LOG_DIR%\frontend.log"
cd /d "%FRONTEND_DIR%"
set "PORT=%FRONTEND_PORT%"
set "HOSTNAME=0.0.0.0"
set "NODE_ENV=production"

:loop
if exist "%STOP_FLAG%" goto :eof
:: Keep the log under about 10 MB.
for %%F in ("%LOG%") do if %%~zF GTR 10485760 move /y "%LOG%" "%LOG%.old" >nul
if exist ".next\standalone" goto run
echo [%date% %time%] No standalone build - run "pnpm build" in %FRONTEND_DIR% >> "%LOG%"
goto wait

:: Plain lines, not a ( ) block: inside a block %time% and %errorlevel%
:: would be read once, before the server even starts.
:run
echo [%date% %time%] Frontend starting on port %FRONTEND_PORT% >> "%LOG%"
node scripts\start-standalone.mjs >> "%LOG%" 2>&1
echo [%date% %time%] Frontend stopped (exit code %errorlevel%) >> "%LOG%"

:wait
if exist "%STOP_FLAG%" goto :eof
:: Wait 10 s. (timeout.exe fails at once when there is no console window,
:: as under Task Scheduler; ping works everywhere.)
ping -n 11 127.0.0.1 >nul
goto loop
