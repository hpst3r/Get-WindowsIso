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

Every run writes a machine-readable summary to logs\last-run-stub.json (and
logs\stub-<timestamp>.json beside the transcript) for notifications.
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

$Started = Get-Date
$Stamp = $Started.ToString('yyyyMMdd-HHmmss')
$LogDirectory = New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'logs')
$TranscriptPath = Join-Path $LogDirectory "stub-$Stamp.log"
Start-Transcript -Path $TranscriptPath | Out-Null

$Mutex = New-Object System.Threading.Mutex($false, 'Global\Get-WindowsIso-Stub')
$Results = [System.Collections.Generic.List[object]]::new()
$ExitCode = 1
$RunError = $null

# build/id from a published <name>.iso.json, or $null
function Get-PublishedInfo([string] $Version) {
  $Path = Join-Path $Config.OutputDirectory "$($Version -replace '\s', '').iso.json"
  if (-not (Test-Path $Path)) { return $null }
  try {
    $Json = Get-Content -Raw $Path | ConvertFrom-Json
    [PSCustomObject]@{ Build = Get-ConfigValue $Json 'build'; Id = Get-ConfigValue (Get-ConfigValue $Json 'uupDump') 'id' }
  }
  catch { Write-Warning "stub: could not read $($Path): $_"; $null }
}

# UTF-8 without BOM; last-run-stub.json is replaced in one step so readers never see half a file
function Write-RunSummary($Summary) {
  $Json = $Summary | ConvertTo-Json -Depth 6
  $Utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $LogDirectory "stub-$Stamp.json"), $Json, $Utf8)
  $Latest = Join-Path $LogDirectory 'last-run-stub.json'
  [System.IO.File]::WriteAllText("$Latest.tmp", $Json, $Utf8)
  Move-Item "$Latest.tmp" $Latest -Force
}

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
        $Before = Get-PublishedInfo $Build.Version
        $Status = if ($Build.Process.ExitCode -eq 0) { Publish-Build $Build.Version } else { "Failed (exit $($Build.Process.ExitCode))" }
        $After = Get-PublishedInfo $Build.Version
        Write-Host "stub: $($Build.Version): $Status after $([math]::Round($Elapsed.TotalMinutes)) minutes."
        $Results.Add([PSCustomObject]@{
            Version       = $Build.Version
            Status        = $Status
            Minutes       = [math]::Round($Elapsed.TotalMinutes)
            # published build after this run, and the one it replaced
            Build         = if ($After) { $After.Build } else { $null }
            PreviousBuild = if ($Status -eq 'Published' -and $Before) { $Before.Build } else { $null }
          })
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
  $RunError = "$_"
  Write-Host "stub: FAILED: $_"
}
finally {
  Write-Host 'stub: summary:'
  $Results | Format-Table Version, Status, Minutes, Build -AutoSize | Out-String | Write-Host

  try {
    $GitVersion = try { git -c safe.directory='*' -C $PSScriptRoot rev-parse --short HEAD 2>$null } catch { $null }
    $Ended = Get-Date
    Write-RunSummary ([PSCustomObject]@{
        stage    = 'stub'
        version  = $GitVersion
        computer = $env:COMPUTERNAME
        started  = $Started.ToString('o')
        ended    = $Ended.ToString('o')
        minutes  = [math]::Round(($Ended - $Started).TotalMinutes, 1)
        exitCode = $ExitCode
        error    = $RunError
        logFile  = $TranscriptPath
        items    = @($Results | ForEach-Object {
            [PSCustomObject]@{
              name          = $_.Version
              status        = $_.Status
              # Published | UpToDate | Failed
              result        = if ($_.Status -like 'Failed*') { 'Failed' } else { $_.Status }
              minutes       = $_.Minutes
              warnings      = 0
              build         = $_.Build
              previousBuild = $_.PreviousBuild
            }
          })
      })
  }
  catch { Write-Warning "stub: could not write the run summary: $_" }

  try { $Mutex.ReleaseMutex() } catch { }
  $Mutex.Dispose()
  Stop-Transcript | Out-Null
}

exit $ExitCode
