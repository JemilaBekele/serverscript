@echo off
:: ============================================================================
::  AFET Dental Care - shared settings for all server scripts.
::  Edit the values in this block only. Every other script reads them.
:: ============================================================================

:: Folder that holds smartdent-backend and smartdent-frontend
:: (default: the folder above this server-scripts folder).
if not defined SYSTEM_DIR for %%I in ("%~dp0..") do set "SYSTEM_DIR=%%~fI"

:: Port staff open in the browser: http://<this-pc-ip>:3090
if not defined FRONTEND_PORT set "FRONTEND_PORT=3090"

:: Where backups go. A second drive or external disk is safer than C:.
if not defined BACKUP_ROOT set "BACKUP_ROOT=C:\AFET-Backups"

:: Delete database backups older than this many days.
:: 0 = never delete: every backup is kept (watch the free disk space).
if not defined KEEP_DAYS set "KEEP_DAYS=0"

:: MongoDB Database Tools (mongodump / mongorestore).
if not defined MONGO_TOOLS set "MONGO_TOOLS=C:\Program Files\MongoDB\Tools\100\bin"

:: ---------------------------------------------------------------------------
::  Derived values - no need to edit below this line.
:: ---------------------------------------------------------------------------
set "BACKEND_DIR=%SYSTEM_DIR%\smartdent-backend"
set "FRONTEND_DIR=%SYSTEM_DIR%\smartdent-frontend"
set "LOG_DIR=%~dp0logs"
set "STOP_FLAG=%~dp0logs\STOP"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Read PORT, MONGODB_URI and IMAGE_UPLOAD_DIR from the backend .env
:: (values already set in the environment win, as they do for the backend).
set "ENV_PORT="
set "ENV_MONGO="
set "ENV_UPLOADS="
if exist "%BACKEND_DIR%\.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%BACKEND_DIR%\.env") do (
    if /i "%%a"=="PORT" set "ENV_PORT=%%b"
    if /i "%%a"=="MONGODB_URI" set "ENV_MONGO=%%b"
    if /i "%%a"=="IMAGE_UPLOAD_DIR" set "ENV_UPLOADS=%%b"
  )
)
if not defined BACKEND_PORT set "BACKEND_PORT=%ENV_PORT%"
if not defined BACKEND_PORT set "BACKEND_PORT=5000"
if not defined MONGO_URI set "MONGO_URI=%ENV_MONGO%"
if not defined ENV_UPLOADS set "ENV_UPLOADS=uploads"

:: Relative upload folders resolve against the backend folder.
set "UPLOADS_DIR=%ENV_UPLOADS%"
if not "%ENV_UPLOADS:~1,1%"==":" set "UPLOADS_DIR=%BACKEND_DIR%\%ENV_UPLOADS%"
