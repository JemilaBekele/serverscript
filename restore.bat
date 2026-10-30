@echo off
:: ============================================================================
::  drlemlem - restore the database from a backup.
::
::  restore.bat                       restores the newest backup
::  restore.bat 2026-10-21_2100       restores that backup folder
::
::  Restores into the database in the backend .env (MONGODB_URI).
::  Patient images: copy BACKUP_ROOT\uploads-mirror back to the uploads folder.
:: ============================================================================
call "%~dp0config.bat"

set "CHOSEN=%~1"
if "%CHOSEN%"=="" (
  for /f "delims=" %%i in ('dir /b /ad "%BACKUP_ROOT%" ^| findstr /v /i "uploads-mirror" ^| "%SystemRoot%\System32\sort.exe" /r') do (
    set "CHOSEN=%%i"
    goto :found
  )
)
:found
if "%CHOSEN%"=="" (
  echo No backup found in %BACKUP_ROOT%
  pause
  exit /b 1
)
if not exist "%BACKUP_ROOT%\%CHOSEN%\db" (
  echo Backup folder not found: %BACKUP_ROOT%\%CHOSEN%\db
  pause
  exit /b 1
)

echo.
echo   Backup : %BACKUP_ROOT%\%CHOSEN%
echo   Into   : the database in %BACKEND_DIR%\.env
echo.
echo   1 = Replace: current data is replaced by the backup (full restore)
echo   2 = Merge  : only records missing from the database are added
echo.
set "MODE="
set /p "MODE=Choose 1 or 2: "
set "DROP="
if "%MODE%"=="1" (
  set "DROP=--drop"
) else if not "%MODE%"=="2" (
  echo Cancelled. Nothing was changed.
  pause
  exit /b 0
)

set /p "CONFIRM=Type YES to start the restore: "
if /i not "%CONFIRM%"=="YES" (
  echo Cancelled. Nothing was changed.
  pause
  exit /b 0
)

echo Stop the system first so nobody saves data during the restore.
call "%~dp0stop-system.bat"

:: The backup holds one folder per database (e.g. db\smartdent). When the
:: address names a database (.../smartdent), mongorestore must be pointed at
:: that folder, otherwise it skips it and restores nothing.
set "RESTORE_DIR=%BACKUP_ROOT%\%CHOSEN%\db"
set "DB_FOLDERS=0"
for /d %%D in ("%BACKUP_ROOT%\%CHOSEN%\db\*") do (
  set /a DB_FOLDERS+=1
  set "ONLY_DB=%%D"
)
if "%DB_FOLDERS%"=="1" set "RESTORE_DIR=%ONLY_DB%"

"%MONGO_TOOLS%\mongorestore.exe" --uri="%MONGO_URI%" --gzip %DROP% --dir="%RESTORE_DIR%"
if errorlevel 1 goto restore_failed
echo.
echo Restore completed.
goto restart

:restore_failed
echo.
echo Restore reported errors - check the messages above.

:restart

echo Starting the system again...
call "%~dp0start-system.bat"
pause
