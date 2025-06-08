#Requires -Version 5.1 -RunAsAdministrator

<#
.SYNOPSIS
Creates a Windows ISO with uupdump.

.INPUTS
[string]$Target:
  The target build of Windows - for example,
  "Windows 11 Professional, version 24H2" for Windows 11 Pro, version 24H2, or
  "Windows Server 2025 Datacenter (Core)" for Windows Server 2025 Datacenter Core.

  All options:

  Windows 11 Professional, version 23H2
  Windows 11 Enterprise, version 23H2
  Windows 11 Professional, version 24H2
  Windows 11 Enterprise, version 24H2
  Windows Server 2025
  Windows Server 2025 Datacenter
  Windows Server 2025 Datacenter (Core)
  Windows Server 2025 Standard
  Windows Server 2025 Standard (Core)
  Windows Server 2022
  Windows Server 2022 Datacenter
  Windows Server 2022 Datacenter (Core)
  Windows Server 2022 Standard
  Windows Server 2022 Standard (Core)

[string]$Path:
  The output path where the ISO will be built.

.OUTPUTS
Windows ISO

.EXAMPLE
.\uup-dump-get-windows-iso.ps1 -Target 'Windows 11 Professional, version 24H2'
#>
param(
    # The target build of Windows, e.g. 24H2 or 2025
    [Parameter(Mandatory = $true)]
    [string]$Target,
    # The name of the child directory to use for the uupdump build job
    [Parameter]
    [string]$Path='output'
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

trap {

    Write-Error $_

    @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1') | Write-Host

    @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1') | Write-Host

    exit 1

}

# the OS build targets available as options for the $Target parameter.
$TARGETS = @{
  # TODO: add All Editions W11 options
  'Windows 11 Professional, version 23H2' = @{
    Search = 'Windows 11, version 23H2'
    Edition = 'Professional'
    VirtualEdition = $null
  }
  'Windows 11 Enterprise, version 23H2' = @{
    Search = 'Windows 11, version 23H2'
    Edition = 'Professional'
    VirtualEdition = 'Enterprise'
  }
  'Windows 11 Professional, version 24H2' = @{
    Search = 'Windows 11, version 24H2'
    Edition = 'Professional'
    VirtualEdition = $null
  }
  'Windows 11 Enterprise, version 24H2' = @{
    Search = 'Windows 11, version 24H2'
    Edition = 'Professional'
    VirtualEdition = 'Enterprise'
  }
  # TODO: add support for Windows Server back THIS NEEDS TESTING
  # TODO: add All Editions WS options
  'Windows Server 2025' = @{
    Search = 'Windows Server 2025'
    Edition = 'serverdatacenter;serverdatacentercore;serverturbine;serverturbinecore;serverstandard;serverstandardcore' # TODO: just make this no edition
  }
  'Windows Server 2025 Datacenter' = @{
    Search = 'Windows Server 2025'
    Edition = 'serverdatacenter' # TODO: could we just parse the name or something lol
  }
  'Windows Server 2025 Datacenter (Core)' = @{
    Search = 'Windows Server 2025'
    Edition = 'serverdatacentercore'
  }
  'Windows Server 2025 Standard' = @{
    Search = 'Windows Server 2025'
    Edition = 'serverstandard'
  }
  'Windows Server 2025 Standard (Core)' = @{
    Search = 'Windows Server 2025'
    Edition = 'serverstandardcore'
  }
  'Windows Server 2022' = @{
    Search = 'Microsoft server operating system, version 21H2'
    Edition = 'serverdatacenter;serverdatacentercore;serverturbine;serverturbinecore;serverstandard;serverstandardcore'
  }
  'Windows Server 2022 Datacenter' = @{
    Search = 'Microsoft server operating system, version 21H2'
    Edition = 'serverdatacenter'
  }
  'Windows Server 2022 Datacenter (Core)' = @{
    Search = 'Microsoft server operating system, version 21H2'
    Edition = 'serverdatacentercore'
  }
  'Windows Server 2022 Standard' = @{
    Search = 'Microsoft server operating system, version 21H2'
    Edition = 'serverstandard'
  }
  'Windows Server 2022 Standard (Core)' = @{
    Search = 'Microsoft server operating system, version 21H2'
    Edition = 'serverstandardcore'
  }
}

<#
.SYNOPSIS
Wrapper to convert a hashtable of parameters to a url encoded string.
#>
function New-QueryString([hashtable]$Parameters) {

    @($Parameters.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
    }) -join '&'

}

<#
.SYNOPSIS
Wrapper to retry uupdump API calls 15 times at 10s interval

.INPUTS
Name: [string]
  GET request to make

Body: [hashtable]
  GET request body
#>
function Invoke-UupDumpApi([string]$Name, [hashtable]$Body) {

  for ($n = 0; $n -lt 15; ++$n) {

    if ($n) {

      Write-Host "Waiting 10s before retrying the uup-dump api $($Name) request #$($n)"
      Start-Sleep -Seconds 10
      Write-Host "Retrying the uup-dump api $($Name) request #$($n)"

    }

    try {

      $Response = Invoke-RestMethod `
        -Method Get `
        -Uri "https://api.uupdump.net/$($Name).php" `
        -Body $Body

      return $Response

    } catch {

      Write-Warning "Failed the uup-dump api $($Name) request: $($_)"

    }

  }

  throw "Failed to make uup-dump api $($Name) request after $($n) attempts. Possible timeout?"

}

function Get-UupDumpIso($Name, $Target) {

  Write-Host "Getting the $($Name) metadata"
  $Result = Invoke-UupDumpApi listId @{ Search = $Target.Search }

  $Result.Response.Builds.PSObject.Properties `
    | ForEach-Object {
      $Id = $_.Value.uuid
      Write-Host "Processing $($Name) $($Id)"
      $_
    } `
    | Where-Object {
      $Result = $Target.Search -like '*preview*' -or $_.Value.Title -notlike '*preview*'
      if (!$Result) {
        Write-Host "Skipping. Expected preview=false. Got preview=true."
      }
      $Result
    } `
    | ForEach-Object {
      $Id = $_.Value.uuid
      Write-Host "Getting $($Name) $($Id) language metadata"
      $Result = Invoke-UupDumpApi listLangs @{ Id = $Id }

      if ($Result.Response.updateInfo.Build -ne $_.Value.Build) {
        throw 'Unexpected Build mismatch in listLangs'
      }

      $_.Value | Add-Member -NotePropertyMembers @{
        Langs = $Result.Response.langFancyNames
        info = $Result.Response.updateInfo
      }

      $Langs = $_.Value.Langs.PSObject.Properties.Name
      $Editions = if ($Langs -contains 'en-us') {
        Write-Host "Getting the $($Name) $($Id) Editions metadata"
        $Result = Invoke-UupDumpApi listEditions @{ Id = $Id; lang = 'en-us' }
        $Result.Response.EditionFancyNames
      } else {
        Write-Host "Skipping. Missing en-us language."
        [PSCustomObject]@{}
      }

      $_.Value | Add-Member -NotePropertyMembers @{ Editions = $Editions }
      $_
  } `
  | Where-Object {
    $Ring = $_.Value.info.Ring
    $Langs = $_.Value.Langs.PSObject.Properties.Name
    $Editions = $_.Value.Editions.PSObject.Properties.Name
    $ExpectedRing = 'RETAIL' # TODO: add support for Dev channel 25H2

    ($Ring -eq $ExpectedRing) -and
    ($Langs -contains 'en-us') -and
    ($Editions -contains $Target.Edition)
  } `
  | Select-Object -First 1 `
  | ForEach-Object {
    $Id = $_.Value.uuid
    [PSCustomObject]@{
      Name = $Name
      Title = $_.Value.Title
      Build = $_.Value.Build
      Id = $Id
      Edition = $Target.Edition
      VirtualEdition = $null
      ApiUrl = 'https://api.uupdump.net/get.php?' + (New-QueryString @{
        Id = $Id; lang = 'en-us'; Edition = $Target.Edition
      })
      DownloadUrl = 'https://uupdump.net/download.php?' + (New-QueryString @{
        Id = $Id; Pack = 'en-us'; Edition = $Target.Edition
      })
      DownloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{
        Id = $Id; Pack = 'en-us'; Edition = $Target.Edition
      })
    }
  }
}

function Get-IsoWindowsImages($IsoPath) {

  $IsoPath = Resolve-Path $IsoPath

  Write-Host "Mounting $IsoPath"

  $IsoImage = Mount-DiskImage $IsoPath -PassThru

  try {

    $IsoVolume = $IsoImage | Get-Volume
    $installPath = "$($IsoVolume.DriveLetter):\sources\install.wim"

    Write-Host "Getting Windows images from $installPath"

    Get-WindowsImage -ImagePath $installPath | ForEach-Object {

      $Image = Get-WindowsImage -ImagePath $installPath -Index $_.ImageIndex

      [PSCustomObject]@{
        Index = $Image.ImageIndex
        Name = $Image.ImageName
        Version = $Image.Version
      }

    }

  } finally {

    Write-Host "Dismounting $IsoPath"
    Dismount-DiskImage $IsoPath | Out-Null

  }

}

function Get-WindowsIso($Name, $Path) {

  $Iso = Get-UupDumpIso $Name $TARGETS.$Name

  if ($Iso.Build -notmatch '^\d+\.\d+$') {
    throw "unexpected $($Name) Build: $($Iso.Build)"
  }

  $BuildDirectory = (Join-Path -Path $Path -ChildPath $Name)
  $DestinationIsoPath = "$($BuildDirectory).Iso"
  $DestinationIsoMetadataPath = "$($DestinationIsoPath).json"
  $DestinationIsoChecksumPath = "$($DestinationIsoPath).sha256.txt"

  if (Test-Path $BuildDirectory) {
      Remove-Item -Force -Recurse $BuildDirectory | Out-Null
  }

  New-Item -ItemType Directory -Force $BuildDirectory | Out-Null

  $Title = "$($Name) $($Iso.Edition) $($Iso.Build)"
  Write-Host "Downloading UUP dump package for $($Title)"

  $DownloadPackageBody = @{
    autodl = 2
    updates = 1
    cleanup = 1
  }

  Invoke-WebRequest `
    -Method Post `
    -Uri $Iso.DownloadPackageUrl `
    -Body $DownloadPackageBody `
    -OutFile "$BuildDirectory.zip" |
    Out-Null
  
  Expand-Archive `
    -Path "$BuildDirectory.zip" `
    -DestinationPath $BuildDirectory

  $convertConfig = (Get-Content $BuildDirectory/ConvertConfig.ini) `
    -replace '^(AutoExit\s*)=.*','$1=1' `
    -replace '^(Cleanup\s*)=.*','$1=1' `
    -replace '^(NetFx3\s*)=.*','$1=1' `
    -replace '^(ResetBase\s*)=.*','$1=1' `
    -replace '^(SkipWinRE\s*)=.*','$1=1'

  Set-Content `
    -Encoding ascii `
    -Path (Join-Path -Path $BuildDirectory -ChildPath ConvertConfig.ini) `
    -Value $convertConfig

  Write-Host "Creating ISO for $($Title)"

  Push-Location $BuildDirectory

  powershell cmd /c uup_download_windows.cmd | Out-String -Stream

  if ($LASTEXITCODE) {
    throw "uup_download_windows.cmd failed with exit code $LASTEXITCODE"
  }

  Pop-Location

  $SourceIsoPath = Resolve-Path $BuildDirectory/*.Iso

  $IsoChecksum = (Get-FileHash -Algorithm SHA256 $SourceIsoPath).Hash.ToLowerInvariant()
  Set-Content -Encoding ascii -NoNewline -Path $DestinationIsoChecksumPath -Value $IsoChecksum

  $windowsImages = Get-IsoWindowsImages $SourceIsoPath

  Set-Content -Path $DestinationIsoMetadataPath -Value (
    ([PSCustomObject]@{
      Name = $Name
      Title = $Iso.Title
      Build = $Iso.Build
      checksum = $IsoChecksum
      Images = @($windowsImages)
      uupDump = @{
        Id = $Iso.Id
        ApiUrl = $Iso.ApiUrl
        DownloadUrl = $Iso.DownloadUrl
        DownloadPackageUrl = $Iso.DownloadPackageUrl
      }
    } | ConvertTo-Json -Depth 99) -replace '\\u0026','&'
  )

  Write-Host "Moving ISO to $DestinationIsoPath"
  Move-Item -Force $SourceIsoPath $DestinationIsoPath

  Write-Host 'All Done.'

}

Start-Transcript `
  -Path "job-$(Get-Date -UFormat %s).log"

Get-WindowsIso $Target $Path

Stop-Transcript