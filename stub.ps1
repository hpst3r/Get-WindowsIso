#Requires -Version 5.1 -RunAsAdministrator

<#
.SYNOPSIS
Builds an ISO for every version in config.json and publishes the ones that succeed.

.DESCRIPTION
Builds run one at a time by default. uupdump's converter always mounts images
at <drive>:\MountUUP and uses <drive>:\W10UIuup as scratch, so two conversions
on the same drive corrupt each other. Only raise MaxParallel if each build has
its own drive. Launches are at least 60 seconds apart to stay under the
uupdump API rate limit. A version whose published ISO is already the latest
build is skipped without downloading anything.

Only versions whose build exits 0 are published, so a failed build never
replaces last week's good ISO. Exit code is 0 if every version succeeded.
#>
param (
  [switch]$NoNewWindow,
  [string]$ConfigFile = (Join-Path $PSScriptRoot 'config.json'),
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BuildScript = Join-Path $PSScriptRoot 'uup-dump-get-windows-iso.ps1'
$Config = Get-Content -Raw $ConfigFile | ConvertFrom-Json

function Get-ConfigValue($Object, [string] $Name, $Default = $null) {
  if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $Default }
}

$MaxParallel = [int](Get-ConfigValue $Config 'MaxParallel' 1)
$TimeoutHours = [double](Get-ConfigValue $Config 'TimeoutHoursPerVersion' 4)
$LaunchInterval = [TimeSpan]::FromSeconds(60)

$LogDirectory = New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'logs')
Start-Transcript -Path (Join-Path $LogDirectory "stub-$(Get-Date -Format yyyyMMdd-HHmmss).log") | Out-Null

$Mutex = New-Object System.Threading.Mutex($false, 'Global\Get-WindowsIso-Stub')
$Results = [System.Collections.Generic.List[object]]::new()
$ExitCode = 1

# move a finished build's ISO and sidecars from the working directory to the output directory
function Publish-Build([string] $Version) {
  $BaseName = "$($Version -replace '\s', '').iso"
  $Source = Join-Path $Config.WorkingDirectory $BaseName
  $Destination = Join-Path $Config.OutputDirectory $BaseName

  if (-not (Test-Path $Source)) { return 'UpToDate' }

  # drop the old sidecars first so they never describe the wrong ISO
  foreach ($Suffix in '.json', '.sha256.txt') {
    if (Test-Path "$Destination$Suffix") { Remove-Item "$Destination$Suffix" -Force }
  }
  Move-Item $Source $Destination -Force
  foreach ($Suffix in '.json', '.sha256.txt') {
    if (Test-Path "$Source$Suffix") { Move-Item "$Source$Suffix" "$Destination$Suffix" -Force }
  }
  'Published'
}

try {
  $Acquired = try { $Mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $true }
  if (-not $Acquired) { throw 'stub: another stub is already running. Exiting.' }

  # clean up after a previous run that was killed mid-conversion. The converter
  # mounts at <drive>:\MountUUP (drive of the build directory), not under it.
  $Drive = Split-Path -Qualifier (New-Item -ItemType Directory -Force -Path $Config.WorkingDirectory).FullName
  $ConverterMount = "$Drive\MountUUP"
  foreach ($Image in @(Get-WindowsImage -Mounted)) {
    if ($Image.Path -like "$($Config.WorkingDirectory)*" -or $Image.Path -eq $ConverterMount -or $Image.ImagePath -like "$($Config.WorkingDirectory)*") {
      Write-Host "stub: discarding stale mount $($Image.Path) ($($Image.ImagePath))."
      Dismount-WindowsImage -Path $Image.Path -Discard -ErrorAction Continue | Out-Null
    }
  }
  Clear-WindowsCorruptMountPoint | Out-Null
  foreach ($Path in $ConverterMount, "$Drive\W10UIuup") {
    if (Test-Path $Path) { Remove-Item $Path -Recurse -Force -ErrorAction Continue }
  }

  if (Test-Path $Config.WorkingDirectory) { Remove-Item $Config.WorkingDirectory -Force -Recurse }
  New-Item -ItemType Directory -Force -Path $Config.WorkingDirectory, $Config.OutputDirectory | Out-Null

  $Pending = [System.Collections.Generic.Queue[string]]::new([string[]]@($Config.Versions))
  $Running = [System.Collections.Generic.List[object]]::new()
  $LastLaunch = [DateTime]::MinValue

  while ($Pending.Count -or $Running.Count) {

    foreach ($Build in @($Running)) {
      $Elapsed = (Get-Date) - $Build.Started

      if (-not $Build.Process.HasExited -and $Elapsed.TotalHours -gt $TimeoutHours) {
        Write-Warning "stub: $($Build.Version) exceeded $TimeoutHours hours. Killing it."
        & taskkill.exe /T /F /PID $Build.Process.Id | Out-Null
        $Build.Process.WaitForExit()
      }

      if ($Build.Process.HasExited) {
        $Running.Remove($Build) | Out-Null
        $Status = if ($Build.Process.ExitCode -eq 0) { Publish-Build $Build.Version } else { "Failed (exit $($Build.Process.ExitCode))" }
        Write-Host "stub: $($Build.Version): $Status after $([math]::Round($Elapsed.TotalMinutes)) minutes."
        $Results.Add([PSCustomObject]@{ Version = $Build.Version; Status = $Status; Minutes = [math]::Round($Elapsed.TotalMinutes) })
      }
    }

    if ($Pending.Count -and $Running.Count -lt $MaxParallel -and ((Get-Date) - $LastLaunch) -ge $LaunchInterval) {
      $Version = $Pending.Dequeue()
      Write-Host "stub: starting $($Version)."

      $Arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$BuildScript`"",
        '-Version', "`"$Version`"",
        '-Path', "`"$($Config.WorkingDirectory)`"",
        '-PublishedDirectory', "`"$($Config.OutputDirectory)`""
      )
      if ($Force) { $Arguments += '-Force' }

      $Process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList $Arguments `
        -WorkingDirectory $PSScriptRoot `
        -PassThru `
        -NoNewWindow:$NoNewWindow

      # Windows PowerShell only reports ExitCode for a -PassThru process if its
      # handle was opened while it was running; without this ExitCode is $null
      $null = $Process.Handle

      $Running.Add([PSCustomObject]@{ Version = $Version; Process = $Process; Started = Get-Date })
      $LastLaunch = Get-Date
      continue
    }

    Start-Sleep -Seconds 10
  }

  $ExitCode = if (@($Results | Where-Object Status -like 'Failed*').Count) { 1 } else { 0 }

  Write-Host "stub: removing working directory $($Config.WorkingDirectory)."
  Remove-Item $Config.WorkingDirectory -Force -Recurse -ErrorAction Continue
}
catch {
  Write-Host "stub: FAILED: $_"
}
finally {
  Write-Host 'stub: summary:'
  $Results | Format-Table -AutoSize | Out-String | Write-Host
  try { $Mutex.ReleaseMutex() } catch { }
  $Mutex.Dispose()
  Stop-Transcript | Out-Null
}

exit $ExitCode
