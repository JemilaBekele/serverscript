# AFET Dental Care - register the Task Scheduler tasks.
# Run once, as Administrator:  right-click install-tasks.bat > Run as administrator
#
#   "SmartDent\Start System" - at Windows start-up (no login needed), runs RunServer.vbs
#   "SmartDent\Daily Backup" - every day at $BackupTime, runs RunBackup.vbs;
#                              if the PC was off at that time it runs at next start-up
param([string]$BackupTime = "21:00")

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

# Older versions registered the tasks under "AFET Dental". Remove those, so the
# system is not started twice at boot or backed up twice a day.
Get-ScheduledTask -TaskPath "\AFET Dental\" -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false

$startTrigger = New-ScheduledTaskTrigger -AtStartup
$startTrigger.Delay = "PT1M"   # give the network and MongoDB a minute to come up
Register-ScheduledTask -TaskPath "\SmartDent\" -TaskName "Start System" -Force `
    -Action (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunServer.vbs`"") `
    -Trigger $startTrigger -Principal $principal -Settings $settings | Out-Null

Register-ScheduledTask -TaskPath "\SmartDent\" -TaskName "Daily Backup" -Force `
    -Action (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunBackup.vbs`"") `
    -Trigger (New-ScheduledTaskTrigger -Daily -At $BackupTime) -Principal $principal -Settings $settings | Out-Null

Write-Host "Registered: \SmartDent\Start System  (at start-up)"
Write-Host "Registered: \SmartDent\Daily Backup  (daily at $BackupTime)"
