# drlemlem - register the Task Scheduler tasks.
# Run once, as Administrator:  right-click install-tasks.bat > Run as administrator
#
#   "SmartDent\Start System" - at Windows start-up (no login needed), runs RunServer.vbs
#   "SmartDent\Backup"       - every $BackupEveryHours hour(s), runs RunBackup.vbs;
#                              if the PC was off at that time it runs at next start-up
param([int]$BackupEveryHours = 1)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
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
