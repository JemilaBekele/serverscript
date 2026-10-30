@echo off
:: ============================================================================
::  drlemlem - back up the database and the patient images.
::
::  Database : BACKUP_ROOT\<date_time>\db   (compressed mongodump)
::  Images   : BACKUP_ROOT\uploads-mirror    (new and changed files added,
::             nothing ever deleted from the copy)
::  Database backups older than KEEP_DAYS days are removed (KEEP_DAYS=0:
::  none are ever removed).
::  Run hidden through RunBackup.vbs (Task Scheduler) or double-click this.
:: ============================================================================
call "%~dp0config.bat"
set "LOG=%LOG_DIR%\backup.log"
:: Keep the log under about 10 MB (it grows every hour).
for %%F in ("%LOG%") do if %%~zF GTR 10485760 move /y "%LOG%" "%LOG%.old" >nul

for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmm"') do set "STAMP=%%d"
set "TARGET=%BACKUP_ROOT%\%STAMP%"

echo. >> "%LOG%"
echo [%date% %time%] Backup started: %TARGET% >> "%LOG%"

if not defined MONGO_URI (
  echo [%date% %time%] FAILED: MONGODB_URI not found in %BACKEND_DIR%\.env >> "%LOG%"
  exit /b 1
)
if not exist "%MONGO_TOOLS%\mongodump.exe" (
  echo [%date% %time%] FAILED: mongodump.exe not found in %MONGO_TOOLS% >> "%LOG%"
  exit /b 1
)

mkdir "%TARGET%" 2>nul
"%MONGO_TOOLS%\mongodump.exe" --uri="%MONGO_URI%" --gzip --out="%TARGET%\db" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo [%date% %time%] FAILED: mongodump returned an error - see above >> "%LOG%"
  exit /b 1
)
echo [%date% %time%] Database saved >> "%LOG%"

if not exist "%UPLOADS_DIR%" goto prune
robocopy "%UPLOADS_DIR%" "%BACKUP_ROOT%\uploads-mirror" /E /R:2 /W:5 /NP /NFL /NDL >> "%LOG%"
:: robocopy: 0-7 = success, 8 or more = some files failed.
if errorlevel 8 echo [%date% %time%] WARNING: some images could not be copied >> "%LOG%"
if not errorlevel 8 echo [%date% %time%] Images copied >> "%LOG%"

:prune

:: Remove old dated backups; the uploads mirror is kept. KEEP_DAYS=0 keeps all.
if "%KEEP_DAYS%"=="0" goto done
forfiles /p "%BACKUP_ROOT%" /d -%KEEP_DAYS% /c "cmd /c if @isdir==TRUE if /i not @file==\"uploads-mirror\" rd /s /q @path" >nul 2>&1

:done
echo [%date% %time%] Backup finished >> "%LOG%"
exit /b 0
