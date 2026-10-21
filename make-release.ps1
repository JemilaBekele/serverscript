# SmartDent - build a release package for clinic servers. SUPPLIER'S PC ONLY.
#
# Builds the backend (bundled + obfuscated, production packages included) and
# the frontend (standalone build), adds these server scripts, and zips it all:
#
#   <Out>\SmartDent-<date_time>.zip
#       smartdent-backend\    dist\, node_modules\, package.json   (no source)
#       smartdent-frontend\   .next\standalone\, scripts\           (no source)
#       server-scripts\
#
# No TypeScript source, no .git, no .env and no license tools are included.
# Install it on the server with install-release.bat.
#
# Usage (PowerShell):  .\make-release.ps1 [-Out C:\SmartDent-Releases] [-BackendPort 7000]
param(
    [string]$Out = "",
    # Must match PORT in the clinic's smartdent-backend\.env (fixed into the build).
    [int]$BackendPort = 7000
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sys = Split-Path -Parent $here
if (-not $Out) { $Out = Join-Path $sys "release" }
$stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
# Built in a short folder: the frontend's packages have very long paths, and
# Windows tools fail past 260 characters.
$dir = Join-Path "$env:SystemDrive\sdrel" $stamp
$zip = Join-Path $Out "SmartDent-$stamp.zip"

# Deletes a folder, including paths longer than 260 characters.
function Remove-Tree([string]$path) {
    if (-not (Test-Path $path)) { return }
    $empty = Join-Path $env:TEMP "sd-empty-$PID"
    New-Item -ItemType Directory -Force $empty | Out-Null
    robocopy $empty $path /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    Remove-Item $path, $empty -Recurse -Force
}

function Invoke-Step([string]$what, [scriptblock]$run) {
    Write-Host "`n=== $what ===" -ForegroundColor Cyan
    & $run
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)" }
}

# 1. Backend
Invoke-Step "Backend" { node (Join-Path $sys "smartdent-backend\scripts\release.mjs") (Join-Path $dir "smartdent-backend") }

# 2. Frontend: the API address is fixed into the build.
$frontend = Join-Path $sys "smartdent-frontend"
$env:NEXT_PUBLIC_API_URL = "/api/v1"
$env:API_PROXY_TARGET = "http://127.0.0.1:$BackendPort"
Push-Location $frontend
try { Invoke-Step "Frontend" { pnpm build } } finally { Pop-Location }

$feOut = Join-Path $dir "smartdent-frontend"
New-Item -ItemType Directory -Force (Join-Path $feOut ".next"), (Join-Path $feOut "scripts") | Out-Null
robocopy (Join-Path $frontend ".next\standalone") (Join-Path $feOut ".next\standalone") /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copying the frontend build failed" }
Copy-Item (Join-Path $frontend "scripts\start-standalone.mjs") (Join-Path $feOut "scripts")
# Next.js copies the build machine's .env files into the standalone folder;
# they are not needed at run time and may hold the supplier's secrets.
Get-ChildItem (Join-Path $feOut ".next\standalone") -Force -Recurse -Depth 1 -File -Filter ".env*" |
    Where-Object { $_.FullName -notmatch "\\node_modules\\" } |
    Remove-Item -Force

# 3. Server scripts (not this release tool, not the logs or git data)
Write-Host "`n=== Server scripts ===" -ForegroundColor Cyan
robocopy $here (Join-Path $dir "server-scripts") /E /XD .git logs /XF make-release.ps1 make-release.bat .gitignore .gitattributes /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copying the server scripts failed" }

# 4. Version note and zip
$commits = foreach ($repo in "smartdent-backend", "smartdent-frontend", "server-scripts") {
    "$repo  $(git -C (Join-Path $sys $repo) rev-parse --short HEAD 2>$null)"
}
@("SmartDent release $stamp", "Backend port: $BackendPort", "") + $commits |
    Set-Content (Join-Path $dir "VERSION.txt") -Encoding utf8

Write-Host "`n=== Zip ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force $Out | Out-Null
Compress-Archive -Path (Join-Path $dir "*") -DestinationPath $zip -CompressionLevel Optimal
Remove-Tree $dir
try { [System.IO.Directory]::Delete("$env:SystemDrive\sdrel") } catch { }   # only if empty

Write-Host "`nRelease ready: $zip" -ForegroundColor Green
Write-Host "Copy it to the server and run:  install-release.bat `"<path to zip>`""
