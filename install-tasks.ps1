# AFET Dental Care - register the Task Scheduler tasks.
# Run once, as Administrator:  right-click install-tasks.bat > Run as administrator
#
#   "AFET Dental\Start System" - at Windows start-up (no login needed), runs RunServer.vbs
#   "AFET Dental\Daily Backup" - every day at $BackupTime, runs RunBackup.vbs;
#                                if the PC was off at that time it runs at next start-up
param([string]$BackupTime = "21:00")

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

$startTrigger = New-ScheduledTaskTrigger -AtStartup
$startTrigger.Delay = "PT1M"   # give the network and MongoDB a minute to come up
Register-ScheduledTask -TaskPath "\AFET Dental\" -TaskName "Start System" -Force `
    -Action (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunServer.vbs`"") `
    -Trigger $startTrigger -Principal $principal -Settings $settings | Out-Null

Register-ScheduledTask -TaskPath "\AFET Dental\" -TaskName "Daily Backup" -Force `
    -Action (New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$here\RunBackup.vbs`"") `
    -Trigger (New-ScheduledTaskTrigger -Daily -At $BackupTime) -Principal $principal -Settings $settings | Out-Null

Write-Host "Registered: \AFET Dental\Start System  (at start-up)"
Write-Host "Registered: \AFET Dental\Daily Backup  (daily at $BackupTime)"
