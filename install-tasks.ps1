# drlemlem - register the Task Scheduler tasks.
# Run once, as Administrator:  right-click install-tasks.bat > Run as administrator
#
#   "SmartDent\Start System" - at Windows start-up (no login needed), runs RunServer.vbs
#   "SmartDent\Backup"       - every $BackupEveryHours hour(s), runs RunBackup.vbs;
#                              if the PC was off at that time it runs at next start-up
#
# It also keeps the server online: no sleep while plugged in, and the
# Cloudflare tunnel restarts if it stops.
param([int]$BackupEveryHours = 1)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

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
Write-Host "Power:      never sleeps or hibernates while plugged in; closing the lid does nothing"

# The Cloudflare tunnel (if installed as a service) starts with Windows and is
# restarted a minute after it stops for any reason.
if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
    sc.exe config cloudflared start= auto | Out-Null
    sc.exe failure cloudflared reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    Write-Host "Cloudflare: tunnel starts with Windows and restarts if it stops"
}

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

# Older versions registered the tasks under "AFET Dental", and the backup as
# "Daily Backup". Remove those, so nothing runs twice.
Get-ScheduledTask -TaskPath "\AFET Dental\" -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false
Get-ScheduledTask -TaskPath "\SmartDent\" -TaskName "Daily Backup" -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false

# A "SmartDent" folder that Task Scheduler still lists but whose folder under
# System32\Tasks was deleted makes Register-ScheduledTask fail with "The system
# cannot find the path specified" (0x80070003). Put the folder back.
$taskDir = Join-Path $env:windir "System32\Tasks\SmartDent"
if ((Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\SmartDent") -and
    -not (Test-Path $taskDir)) {
    New-Item -ItemType Directory -Force $taskDir | Out-Null
}

$startTrigger = New-ScheduledTaskTrigger -AtStartup
$startTrigger.Delay = "PT1M"   # give the network and MongoDB a minute to come up
Register-ScheduledTask -TaskPath "\SmartDent\" -TaskName "Start System" -Force `
    -Action (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunServer.vbs`"") `
    -Trigger $startTrigger -Principal $principal -Settings $settings | Out-Null

# On the hour, every $BackupEveryHours hour(s), with no end date.
$backupTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
    -RepetitionInterval (New-TimeSpan -Hours $BackupEveryHours)
Register-ScheduledTask -TaskPath "\SmartDent\" -TaskName "Backup" -Force `
    -Action (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunBackup.vbs`"") `
    -Trigger $backupTrigger -Principal $principal -Settings $settings | Out-Null

Write-Host "Registered: \SmartDent\Start System  (at start-up)"
Write-Host "Registered: \SmartDent\Backup        (every $BackupEveryHours hour(s))"
