#Requires -Version 5.1 -RunAsAdministrator

<#
.SYNOPSIS
Creates a Windows ISO with uupdump.

.INPUTS
[string]$Version:
  The target build/edition of Windows - for example,
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
    [string]$Version,
    # The name of the child directory to use for the uupdump build job
    [Parameter()]
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
[hashtable]$TARGETS = @{
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
        "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.value))"
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
function Invoke-UupDumpApi {
  param (
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [Parameter(Mandatory=$true)]
    [hashtable]$Body
  )

  for ($n = 0; $n -lt 15; ++$n) {

    if ($n) {

      Write-Host "Waiting 10s before retrying the UUP dump api $($Name) request, attempt $($n)"

      Start-Sleep -Seconds 10

      Write-Host "Retrying the uup-dump api $($Name) request, attempt $($n)"

    }

    try {

      $Uri = "https://api.uupdump.net/$($Name).php"

      Write-Host "Making API request $($Uri) with query: $(New-QueryString -Parameters $Body)"

      $Response = Invoke-RestMethod `
        -Method Get `
        -Uri $Uri `
        -Body $Body
      
      return $Response

    } catch {

      $Failure = $_

      Write-Warning "Failed the uup-dump api $($Name) request: $($Failure)"

    }

  }

  throw "Failed to make uup-dump api $($Name) request after $($n) attempts. Possible timeout?"

}

function Get-UupDumpIso([string]$Name, [hashtable]$Target) {

  Write-Host "Getting metadata for $($Name)."

  Write-Host "Search: $($Target.Search)"
  
  $Result = Invoke-UupDumpApi -Name 'listid' -Body @{ 'search' = $Target.Search }

  $Result.Response.builds.PSObject.Properties `
    | ForEach-Object {
      $Id = $_.value.uuid
      Write-Host "Processing $($Name) $($Id)"
      $_
    } `
    | Where-Object {
      $Result = $Target.Search -like '*preview*' -or $_.value.title -notlike '*preview*'
      if (!$Result) {
        Write-Host "Skipping. Expected preview=false. Got preview=true."
      }
      $Result
    } `
    | ForEach-Object {
      $Id = $_.value.uuid
      Write-Host "Getting $($Name) $($Id) language metadata"
      $Result = Invoke-UupDumpApi listlangs @{ id = $Id }
      Write-Host "Got $($Name) $($Id) language metadata"

      Write-Host $Result.Response

      if ($Result.Response.updateinfo.build -ne $_.value.build) {
        throw 'Unexpected build mismatch in listlangs'
      }
      Write-Host "No build mismatch in $($Name) $($Id) language metadata"

      $_.value | Add-Member -NotePropertyMembers @{
        langs = $Result.Response.langFancyNames
        info = $Result.Response.updateInfo
      }

      $Langs = $_.value.langs.PSObject.Properties.Name
      $Editions = if ($langs -contains 'en-us') {
        Write-Host "Getting the $($Name) $($Id) editions metadata"
        $Result = Invoke-UupDumpApi listeditions @{ id = $Id; lang = 'en-us' }
        $Result.Response.editionFancyNames
      } else {
        Write-Host "Skipping. Missing en-us language."
        [PSCustomObject]@{}
      }

      $_.value | Add-Member -NotePropertyMembers @{ editions = $Editions }
      $_
  } `
  | Where-Object {
    $Ring = $_.value.info.Ring
    $Langs = $_.value.langs.PSObject.Properties.Name
    $Editions = $_.value.editions.PSObject.Properties.Name
    $ExpectedRing = 'RETAIL' # TODO: add support for Dev channel 25H2

    ($Ring -eq $ExpectedRing) -and
    ($Langs -contains 'en-us') -and
    ($Editions -contains $Target.Edition)
  } `
  | Select-Object -First 1 `
  | ForEach-Object {
    $Id = $_.value.uuid
    [PSCustomObject]@{
      Name = $Name
      Title = $_.value.Title
      Build = $_.value.Build
      Id = $Id
      Edition = $Target.Edition
      VirtualEdition = $null # TODO: this probably needs to inherit from $Target
      # build API requests for requested version
      ApiUrl = 'https://api.uupdump.net/get.php?' + (New-QueryString @{
        'id' = $Id
        'lang' = 'en-us'
        'edition' = $Target.Edition
      })
      DownloadUrl = 'https://uupdump.net/download.php?' + (New-QueryString @{
        'id' = $Id
        'pack' = 'en-us'
        'edition' = $Target.Edition
      })
      DownloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{
        'id' = $Id
        'pack' = 'en-us'
        'edition' = $Target.Edition
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
    $InstallPath = "$($IsoVolume.DriveLetter):\sources\install.wim"

    Write-Host "Getting Windows images from $($InstallPath)"

    Get-WindowsImage -ImagePath $InstallPath | ForEach-Object {

      $Image = Get-WindowsImage -ImagePath $InstallPath -Index $_.ImageIndex

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

function Get-WindowsIso([string]$Name, [hashtable]$Target, $Path) {

  $Iso = Get-UupDumpIso -Name $Name -Target $Target

  $Iso | Format-List

  if ($Iso.Build -notmatch '^\d+\.\d+$') {
    throw "unexpected $($Name) build: $($Iso.Build)"
  }

  # Create the build directory. Cannot have spaces in the PATH, so strip them from the Name.
  $BuildDirectory = (Join-Path -Path $Path -ChildPath ($Name -replace '\s',''))
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

  $ConvertConfig = (Get-Content $BuildDirectory/ConvertConfig.ini) `
    -replace '^(AutoExit\s*)=.*','$1=1' `
    -replace '^(Cleanup\s*)=.*','$1=1' `
    -replace '^(NetFx3\s*)=.*','$1=1' `
    -replace '^(ResetBase\s*)=.*','$1=1' `
    -replace '^(SkipWinRE\s*)=.*','$1=1'

  Set-Content `
    -Encoding ascii `
    -Path (Join-Path -Path $BuildDirectory -ChildPath ConvertConfig.ini) `
    -Value $ConvertConfig

  Write-Host "Creating ISO for $($Title)"

  Push-Location $BuildDirectory

  powershell cmd /c uup_download_windows.cmd | Out-String -Stream

  if ($LASTEXITCODE) {
    throw "uup_download_windows.cmd failed with exit code $LASTEXITCODE"
  }

  Pop-Location

  $SourceIsoPath = Resolve-Path $BuildDirectory/*.Iso

  $IsoChecksum = (Get-FileHash -Algorithm SHA256 $SourceIsoPath).Hash.ToLowerInvariant()
  Set-Content -Encoding ascii -NoNewline -Path $DestinationIsoChecksumPath -value $IsoChecksum

  $windowsImages = Get-IsoWindowsImages $SourceIsoPath

  Set-Content -Path $DestinationIsoMetadataPath -value (
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

Get-WindowsIso -Name $Version -Target $TARGETS[$Version] -Path $Path

Stop-Transcript