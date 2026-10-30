# drlemlem - register the Task Scheduler tasks.
# Run once, as Administrator:  right-click install-tasks.bat > Run as administrator
#
#   "SmartDent\Start System" - at Windows start-up (no login needed), runs RunServer.vbs
#   "SmartDent\Backup"       - every $BackupEveryHours hour(s), runs RunBackup.vbs;
#                              if the PC was off at that time it runs at next start-up
#
# It also keeps the server online: no sleep while plugged in, and the
# Cloudflare tunnel restarts if it stops.
#
# Every run is written to logs\install-tasks.log, with what Task Scheduler
# holds before and after and the full error of any step that fails.
param([int]$BackupEveryHours = 1)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $here "logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "install-tasks.log"

function Log([string]$text, [string]$color = "") {
    Add-Content -LiteralPath $log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $text" -Encoding UTF8
    if ($color) { Write-Host $text -ForegroundColor $color } else { Write-Host $text }
}

# Only to the log file: details staff do not need on screen.
function Detail([string]$text) {
    Add-Content -LiteralPath $log -Value "    $text" -Encoding UTF8
}

function Detail-Error($err) {
    $e = $err.Exception
    Detail "error type:  $($e.GetType().FullName)"
    Detail "message:     $($e.Message.Trim())"
    Detail ("hresult:     0x{0:X8}" -f $e.HResult)
    if ($e.InnerException) { Detail "inner:       $($e.InnerException.Message.Trim())" }
    Detail "error id:    $($err.FullyQualifiedErrorId)"
    Detail "category:    $($err.CategoryInfo)"
    Detail "at line:     $($err.InvocationInfo.ScriptLineNumber): $($err.InvocationInfo.Line.Trim())"
}

$cache = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache"
$taskDir = Join-Path $env:windir "System32\Tasks\SmartDent"

# What Task Scheduler holds for SmartDent: the task files, the registry
# entries (and whether each one's details exist), and what it reports.
function Detail-TaskState([string]$when) {
    Detail "--- Task Scheduler state $when ---"
    try {
        if (Test-Path -LiteralPath $taskDir) {
            $files = @(Get-ChildItem -LiteralPath $taskDir -Force | ForEach-Object { $_.Name })
            Detail "folder ${taskDir}: $(if ($files) { $files -join ', ' } else { '(empty)' })"
        } else {
            Detail "folder ${taskDir}: MISSING"
        }
        if (Test-Path -LiteralPath "$cache\Tree\SmartDent") {
            $keys = @(Get-ChildItem -LiteralPath "$cache\Tree\SmartDent")
            if (-not $keys) { Detail "registry Tree\SmartDent: (no tasks)" }
            foreach ($k in $keys) {
                $id = $k.GetValue("Id")
                $hasDetails = if ($id) { Test-Path -LiteralPath "$cache\Tasks\$id" } else { $false }
                Detail "registry Tree\SmartDent\$($k.PSChildName): Id=$id, Tasks entry=$hasDetails, file=$(Test-Path -LiteralPath (Join-Path $taskDir $k.PSChildName))"
            }
        } else {
            Detail "registry Tree\SmartDent: MISSING"
        }
        $tasks = @(Get-ScheduledTask -TaskPath "\SmartDent\" -ErrorAction SilentlyContinue)
        Detail "Get-ScheduledTask \SmartDent\: $(if ($tasks) { ($tasks | ForEach-Object { "$($_.TaskName) [$($_.State)]" }) -join ', ' } else { '(none)' })"
    } catch {
        Detail "could not read the state:"
        Detail-Error $_
    }
}

Add-Content -LiteralPath $log -Value "" -Encoding UTF8
Log "=== install-tasks $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Detail "user: $([Security.Principal.WindowsIdentity]::GetCurrent().Name), administrator: $admin"
Detail "windows: $([Environment]::OSVersion.VersionString), powershell: $($PSVersionTable.PSVersion)"
Detail "Task Scheduler service: $((Get-Service Schedule).Status)"
Detail "scripts folder: $here"

# Keep the server reachable: other branches use it over the internet, and a
# sleeping PC answers no one (the website, the API and the Cloudflare tunnel
# all stop). When plugged in it never sleeps or hibernates, closing a laptop
# lid does nothing, and the screen may still turn off. Done first, so a
# problem with the tasks below cannot skip it.
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
# Lid close action (by GUID: not every PC has the LIDACTION alias): 0 = do nothing.
powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
powercfg /setactive SCHEME_CURRENT
Log "Power:      never sleeps or hibernates while plugged in; closing the lid does nothing"

# The Cloudflare tunnel (if installed as a service) starts with Windows and is
# restarted a minute after it stops for any reason.
if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
    sc.exe config cloudflared start= auto | Out-Null
    sc.exe failure cloudflared reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    Log "Cloudflare: tunnel starts with Windows and restarts if it stops"
} else {
    Detail "no cloudflared service on this PC"
}

Detail-TaskState "before"

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

# Older versions registered the tasks under "AFET Dental", and the backup as
# "Daily Backup". Remove those, so nothing runs twice.
try {
    Get-ScheduledTask -TaskPath "\AFET Dental\" -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
    Get-ScheduledTask -TaskPath "\SmartDent\" -TaskName "Daily Backup" -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
} catch {
    Log "Could not remove the old tasks (see $log)" Yellow
    Detail-Error $_
}

# Task Scheduler keeps each task twice: in the registry (TaskCache) and as a
# file under System32\Tasks. When the files were deleted but the registry still
# lists the task (or the other way round), Register-ScheduledTask fails with
# "The system cannot find the path specified" (0x80070003). Remove such broken
# leftovers of our tasks, so they can be registered again.
foreach ($name in "Start System", "Backup", "Daily Backup") {
    $tree = "$cache\Tree\SmartDent\$name"
    $file = Join-Path $taskDir $name
    try {
        $inRegistry = Test-Path -LiteralPath $tree
        $onDisk = Test-Path -LiteralPath $file
        if ($inRegistry -and -not $onDisk) {
            $id = (Get-ItemProperty -LiteralPath $tree).Id
            Remove-Item -LiteralPath $tree -Recurse -Force
            if ($id) {
                foreach ($kind in "Tasks", "Boot", "Logon", "Plain", "Maintenance") {
                    Remove-Item -LiteralPath "$cache\$kind\$id" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Log "Repaired:   removed the broken registry entry of \SmartDent\$name (Id $id)"
        } elseif ($onDisk -and -not $inRegistry) {
            Remove-Item -LiteralPath $file -Force
            Log "Repaired:   removed the leftover file of \SmartDent\$name"
        }
    } catch {
        Log "Could not repair \SmartDent\$name. Delete it in Task Scheduler, then run this again (see $log)." Yellow
        Detail-Error $_
    }
}

# A \SmartDent\ folder that holds no task yet refuses new ones ("Access is
# denied") is broken, e.g. made by hand under System32\Tasks. Delete it through
# Task Scheduler itself (and any folder left on disk), so registering below
# creates it afresh.
try {
    $ours = @(Get-ScheduledTask -TaskPath "\SmartDent\" -ErrorAction SilentlyContinue)
    if (-not $ours) {
        $broken = $false
        try {
            Register-ScheduledTask -TaskPath "\SmartDent\" -TaskName "SmartDent-Probe" -Force `
                -Action (New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c exit") -ErrorAction Stop | Out-Null
            Unregister-ScheduledTask -TaskPath "\SmartDent\" -TaskName "SmartDent-Probe" -Confirm:$false -ErrorAction Stop
        } catch {
            $broken = $true
            Detail "probe task in \SmartDent\ failed before repair:"
            Detail-Error $_
        }
        if ($broken) {
            $scheduler = New-Object -ComObject Schedule.Service
            $scheduler.Connect()
            try { $scheduler.GetFolder("\").DeleteFolder("SmartDent", 0) } catch { Detail "DeleteFolder: $($_.Exception.Message.Trim())" }
            if (Test-Path -LiteralPath $taskDir) { Remove-Item -LiteralPath $taskDir -Recurse -Force }
            try { $scheduler.GetFolder("\").DeleteFolder("SmartDent", 0) } catch { }
            Log "Repaired:   deleted the broken \SmartDent\ folder in Task Scheduler"
        }
    }
} catch {
    Log "Could not repair the \SmartDent\ folder (see $log)" Yellow
    Detail-Error $_
}

# Registers one task; on failure logs the full error and returns $false.
# -ErrorAction Stop on each Task Scheduler command: they come from a module, so
# the script's $ErrorActionPreference does not reach them, and a failure would
# otherwise only print a message and carry on.
function Register-Logged([string]$name, $action, $trigger) {
    try {
        Register-ScheduledTask -TaskPath "\SmartDent\" -TaskName $name -Force `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Log "FAILED:     \SmartDent\$name - $($_.Exception.Message.Trim())" Red
        Detail-Error $_
        return $false
    }
}

$startTrigger = New-ScheduledTaskTrigger -AtStartup
$startTrigger.Delay = "PT1M"   # give the network and MongoDB a minute to come up
$okStart = Register-Logged "Start System" `
    (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunServer.vbs`"") $startTrigger
if ($okStart) { Log "Registered: \SmartDent\Start System  (at start-up)" }

# On the hour, every $BackupEveryHours hour(s), with no end date.
$backupTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
    -RepetitionInterval (New-TimeSpan -Hours $BackupEveryHours)
$okBackup = Register-Logged "Backup" `
    (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunBackup.vbs`"") $backupTrigger
if ($okBackup) { Log "Registered: \SmartDent\Backup        (every $BackupEveryHours hour(s))" }

if (-not ($okStart -and $okBackup)) {
    # Narrow it down: can a plain task be made in \SmartDent\ at all, and in
    # the top folder? A failure only in \SmartDent\ means that folder is broken.
    foreach ($path in "\SmartDent\", "\") {
        try {
            Register-ScheduledTask -TaskPath $path -TaskName "SmartDent-Probe" -Force `
                -Action (New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c exit") -ErrorAction Stop | Out-Null
            Unregister-ScheduledTask -TaskPath $path -TaskName "SmartDent-Probe" -Confirm:$false -ErrorAction Stop
            Detail "probe task in '$path': OK"
        } catch {
            Detail "probe task in '$path': FAILED"
            Detail-Error $_
        }
    }
    Detail-TaskState "after"
    throw "Task registration failed. Details: $log"
}
Detail-TaskState "after"
