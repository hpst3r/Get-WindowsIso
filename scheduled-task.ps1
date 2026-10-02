#Requires -Version 5.1 -RunAsAdministrator

# Registers stub.ps1 as a weekly scheduled task running as SYSTEM (no stored password).
# If you also use Customize-WindowsIso, use its register-task.ps1 instead: it runs
# this stub and the customization runner in sequence as one task.

$ErrorActionPreference = 'Stop'

$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Stub = Join-Path $PSScriptRoot 'stub.ps1'

$Action = New-ScheduledTaskAction -Execute $PowerShell `
  -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Stub`"" `
  -WorkingDirectory $PSScriptRoot
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Wednesday -At '00:00'
$Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 16) -MultipleInstances IgnoreNew -StartWhenAvailable
$Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName 'WeeklyImageUpdate' -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force
