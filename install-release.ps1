# SmartDent - install a release package on the clinic server.
# Run as Administrator:  install-release.bat "C:\path\to\SmartDent-2026-10-21_1500.zip"
#
#  1. Backs up the database and images (backup.bat).
#  2. Stops the system.
#  3. Puts the new backend and frontend in place. Kept from the old backend:
#     .env, license.key and the image folder (IMAGE_UPLOAD_DIR). Server
#     scripts are updated; config.bat (your settings) is kept.
#  4. Starts the system and checks that it answers.
#  5. Success: the old folders (which may hold source code) are deleted.
#     Failure: the old version is put back and started again.
param(
    [Parameter(Mandatory = $true)][string]$Package,
    # Only for when backup.bat cannot run (e.g. MongoDB tools missing).
    [switch]$SkipBackup
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sys = Split-Path -Parent $here
$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$backend = Join-Path $sys "smartdent-backend"
$frontend = Join-Path $sys "smartdent-frontend"
$oldBackend = "$backend.old-$stamp"
$oldFrontend = "$frontend.old-$stamp"

# Deletes a folder, including paths longer than 260 characters.
function Remove-Tree([string]$path) {
    if (-not (Test-Path $path)) { return }
    $empty = Join-Path $env:TEMP "sd-empty-$PID"
    New-Item -ItemType Directory -Force $empty | Out-Null
    robocopy $empty $path /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    Remove-Item $path, $empty -Recurse -Force
}

# Copies a folder, including paths longer than 260 characters.
function Copy-Tree([string]$from, [string]$to) {
    robocopy $from $to /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copying $from failed" }
}

function Say([string]$text, [string]$color = "Cyan") { Write-Host $text -ForegroundColor $color }

# Value of NAME in a .env file, or $null.
function Get-EnvValue([string]$file, [string]$name) {
    if (-not (Test-Path $file)) { return $null }
    foreach ($line in Get-Content $file) {
        if ($line -match "^\s*$name\s*=\s*(.*?)\s*$") { return $Matches[1].Trim('"', "'") }
    }
    return $null
}

# Things that belong to the clinic, relative to the backend folder.
function Get-KeptItems([string]$backendDir) {
    $items = @(".env", "license.key")
    $uploads = Get-EnvValue (Join-Path $backendDir ".env") "IMAGE_UPLOAD_DIR"
    if (-not $uploads) { $uploads = "uploads" }
    if (-not [System.IO.Path]::IsPathRooted($uploads)) { $items += $uploads }
    return $items
}

function Move-Kept([string]$from, [string]$to, [string[]]$items) {
    foreach ($item in $items) {
        $src = Join-Path $from $item
        if (Test-Path $src) {
            $dst = Join-Path $to $item
            New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
            if (Test-Path $dst) { Remove-Tree $dst }
            Move-Item $src $dst
        }
    }
}

function Stop-System {
    cmd /c "`"$here\stop-system.bat`"" | Out-Null
    # The keep-alive loops (run-backend.bat / run-frontend.bat) only notice the
    # STOP flag within 10 s, and while they run their working folder cannot be
    # renamed. End them now.
    Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
        Where-Object { $_.CommandLine -match "run-(backend|frontend)\.bat" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 3
}

# Renames a folder, retrying for 30 s while something still has it open.
function Rename-Folder([string]$path, [string]$newPath) {
    for ($i = 1; ; $i++) {
        try {
            Rename-Item $path (Split-Path -Leaf $newPath)
            return
        } catch {
            if ($i -ge 10) {
                throw "$path is still in use. Close every Command Prompt, VS Code or File Explorer window open in that folder, then run the install again."
            }
            Start-Sleep -Seconds 3
        }
    }
}

function Start-System {
    cmd /c "schtasks /run /tn `"\SmartDent\Start System`" >nul 2>&1"
    if ($LASTEXITCODE -ne 0) {
        # No task yet (install-tasks.bat never run): start it directly.
        Start-Process -WindowStyle Hidden wscript.exe "`"$here\RunServer.vbs`""
    }
}

function Wait-Healthy([int]$port) {
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $api = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$port/health/ready"
            $web = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:3090/login"
            if ($api.StatusCode -eq 200 -and $web.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 3
    }
    return $false
}

# ── 0. Unpack and check the package ────────────────────────────────────────────
if (-not (Test-Path $Package)) { throw "Package not found: $Package" }
$src = $Package
if ($Package -like "*.zip") {
    # A short folder: the frontend's packages have very long paths.
    $src = Join-Path "$env:SystemDrive\sdrel" "install-$stamp"
    Say "Unpacking $Package ..."
    Expand-Archive $Package $src
}
foreach ($need in "smartdent-backend\dist\server.js", "smartdent-backend\node_modules", "smartdent-frontend\.next\standalone", "server-scripts\start-system.bat") {
    if (-not (Test-Path (Join-Path $src $need))) { throw "Not a SmartDent release package (missing $need)" }
}
if (-not (Test-Path (Join-Path $backend ".env"))) { throw "$backend\.env not found: install on a server that is already set up." }
$port = Get-EnvValue (Join-Path $backend ".env") "PORT"
if (-not $port) { $port = 5000 }

# ── 1. Backup ─────────────────────────────────────────────────────────────────
if (-not $SkipBackup) {
    Say "Backing up the database and images ..."
    cmd /c "`"$here\backup.bat`""
    if ($LASTEXITCODE -ne 0) { throw "Backup failed (see logs\backup.log). Nothing was changed. Fix it, or run again with -SkipBackup." }
}

# ── 2. Stop ───────────────────────────────────────────────────────────────────
Say "Stopping the system ..."
Stop-System

# ── 3. Swap ───────────────────────────────────────────────────────────────────
$kept = Get-KeptItems $backend
$swapped = $false
try {
    Say "Installing the new version ..."
    Rename-Folder $backend $oldBackend
    $swapped = $true
    if (Test-Path $frontend) { Rename-Folder $frontend $oldFrontend }
    Copy-Tree (Join-Path $src "smartdent-backend") $backend
    Copy-Tree (Join-Path $src "smartdent-frontend") $frontend
    Move-Kept $oldBackend $backend $kept

    # Server scripts: everything except the clinic's own settings.
    Get-ChildItem (Join-Path $src "server-scripts") -Force | Where-Object { $_.Name -ne "config.bat" -or -not (Test-Path (Join-Path $here "config.bat")) } |
        Copy-Item -Destination $here -Recurse -Force
    Copy-Item (Join-Path $src "VERSION.txt") $sys -Force -ErrorAction SilentlyContinue
} catch {
    Say "Install failed: $($_.Exception.Message)" Red
    if ($swapped) {
        Say "Putting the previous version back ..." Yellow
        Move-Kept $backend $oldBackend $kept
        foreach ($pair in @(@($backend, $oldBackend), @($frontend, $oldFrontend))) {
            if (Test-Path $pair[1]) {
                if (Test-Path $pair[0]) { Remove-Tree $pair[0] }
                Rename-Item $pair[1] (Split-Path -Leaf $pair[0])
            }
        }
    }
    Start-System
    if ($src -ne $Package) { Remove-Tree $src }
    Say "Nothing was changed: the previous version is running again." Yellow
    exit 1
}

# Register the (possibly updated) Task Scheduler tasks.
& (Join-Path $here "install-tasks.ps1")

# ── 4. Start and check ────────────────────────────────────────────────────────
Say "Starting the system and waiting for it to answer ..."
Start-System
if (Wait-Healthy $port) {
    # ── 5. Remove the old version (and any source code with it) ─────────────
    try {
        Remove-Tree $oldBackend
        Remove-Tree $oldFrontend
    } catch {
        Say "Could not delete $oldBackend / $oldFrontend - delete them by hand (they may contain source code)." Yellow
    }
    if ($src -ne $Package) {
        Remove-Tree $src
        try { [System.IO.Directory]::Delete("$env:SystemDrive\sdrel") } catch { }   # only if empty
    }
    Say "`nSmartDent updated and running." Green
    try {
        $lic = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/api/v1/license").Content | ConvertFrom-Json
        if (-not $lic.data.valid) {
            Say "But this computer is NOT licensed: $($lic.data.reason)." Yellow
            Say "Send this machine ID to your SmartDent supplier: $($lic.data.machineId)" Yellow
            Say "Then copy the license.key you receive to $backend\license.key" Yellow
        }
    } catch { }
} else {
    Say "`nThe new version did not start (see logs\backend.log and logs\frontend.log)." Red
    Say "Putting the previous version back ..." Yellow
    Stop-System
    Move-Kept $backend $oldBackend $kept
    Remove-Tree $backend
    Remove-Tree $frontend
    Rename-Item $oldBackend (Split-Path -Leaf $backend)
    if (Test-Path $oldFrontend) { Rename-Item $oldFrontend (Split-Path -Leaf $frontend) }
    Start-System
    Say "The previous version is running again. Send the log files to your supplier." Yellow
    exit 1
}
