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

  To add a new option, you can test a search string on the uupdump.net main site's search page.

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
  # TODO: VirtualEdition is not currently being used for anything, Enterprise won't work
  'Windows 11, version 23H2' = @{
    Search = 'Windows 11, version 23H2'
    Edition = 'core;professional'
  }
  'Windows 11 Professional, version 23H2' = @{
    Search  = 'Windows 11, version 23H2'
    Edition = 'Professional'
  }
  'Windows 11 Enterprise, version 23H2' = @{
    Search  = 'Windows 11, version 23H2'
    Edition = 'Professional'
    VirtualEdition = 'Enterprise'
  }
  'Windows 11 Professional, version 24H2' = @{
    Search  = 'Windows 11, version 24H2'
    Edition = 'Professional'
  }
  'Windows 11 Enterprise, version 24H2' = @{
    Search  = 'Windows 11, version 24H2'
    Edition = 'Professional'
    VirtualEdition = 'Enterprise'
  }
  'Windows 11 Professional, Preview 26200' = @{
    Search  = 'Windows 11 Insider Preview 10.0.26200'
    Edition = 'Professional'
    Ring    = 'DEV'
  }
  'Windows 11 Enterprise, Preview 26200' = @{
    Search  = 'Windows 11 Insider Preview 10.0.26200'
    Edition = 'Professional'
    VirtualEdition = 'Enterprise'
    Ring    = 'DEV'
  }
  'Windows Server 2025' = @{
    Search  = 'Windows Server 2025'
    Edition = 'serverdatacenter;serverdatacentercore;serverturbine;serverturbinecore;serverstandard;serverstandardcore'
  }
  'Windows Server 2025 Datacenter' = @{
    Search  = 'Windows Server 2025'
    Edition = 'serverdatacenter'
  }
  'Windows Server 2025 Datacenter (Core)' = @{
    Search  = 'Windows Server 2025'
    Edition = 'serverdatacentercore'
  }
  'Windows Server 2025 Standard' = @{
    Search  = 'Windows Server 2025'
    Edition = 'serverstandard'
  }
  'Windows Server 2025 Standard (Core)' = @{
    Search  = 'Windows Server 2025'
    Edition = 'serverstandardcore'
  }
  'Windows Server 2022' = @{
    Search  = 'Microsoft server operating system, version 21H2'
    Edition = 'serverdatacenter;serverdatacentercore;serverturbine;serverturbinecore;serverstandard;serverstandardcore'
  }
  'Windows Server 2022 Datacenter' = @{
    Search  = 'Microsoft server operating system, version 21H2'
    Edition = 'serverdatacenter'
  }
  'Windows Server 2022 Datacenter (Core)' = @{
    Search  = 'Microsoft server operating system, version 21H2'
    Edition = 'serverdatacentercore'
  }
  'Windows Server 2022 Standard' = @{
    Search  = 'Microsoft server operating system, version 21H2'
    Edition = 'serverstandard'
  }
  'Windows Server 2022 Standard (Core)' = @{
    Search  = 'Microsoft server operating system, version 21H2'
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

      Write-Host "Invoke-UupDumpApi: Waiting 10s before retrying the UUP dump api $($Name) request, attempt $($n)"

      Start-Sleep -Seconds 10

      Write-Host "Invoke-UupDumpApi: Retrying the uup-dump api $($Name) request, attempt $($n)"

    }

    try {

      $Uri = "https://api.uupdump.net/$($Name).php"

      Write-Host "Invoke-UupDumpApi: Making API request $($Uri) with query: $(New-QueryString -Parameters $Body).`n"

      $Response = Invoke-RestMethod `
        -Method Get `
        -Uri $Uri `
        -Body $Body
      
      return $Response

    } catch {

      $Failure = $_

      Write-Warning "Invoke-UupDumpApi: Failed the uup-dump api $($Name) request: $($Failure)"

    }

  }

  throw "Invoke-UupDumpApi: Failed to make uup-dump api $($Name) request after $($n) attempts. Possible timeout or incorrect parameters."

}

function Get-UupDumpIso([string]$Name, [hashtable]$Target) {

  Write-Host "Get-UupDumpIso: Getting metadata for $($Name).`n"

  Write-Host "Get-UupDumpIso: Using query: $($Target.Search)`n"
  
  $Result = Invoke-UupDumpApi -Name 'listid' -Body @{ 'search' = $Target.Search }

  $Result.Response.builds.PSObject.Properties `
    | ForEach-Object {
      $Id = $_.value.uuid
      Write-Host "Get-UupDumpIso: Processing $($Name) $($Id)`n"

      $_
    } `
    | Where-Object { # verify that preview is only processed if it was requested

      $Result = ($Target.Search -like '*preview*' -or $_.value.title -notlike '*preview*')

      Write-Host "Get-UupDumpIso: Image $($Name) $($Id) preview state is expected? $($Result)`n"

      if (!$Result) {
        Write-Host "Get-UupDumpIso: Skipping. Expected preview=false. Got preview=true.`n"
      }

      $Result

    } `
    | ForEach-Object { # get lang and edition metadata

      Write-Verbose "Get-UupDumpIso: Current metadata:"
      Write-Verbose ($_.value | ConvertTo-Json -Depth 99) # pretty format as json
      Write-Verbose "`n"

      $Id = $_.value.uuid

      # get language metadata

      Write-Host "Get-UupDumpIso: Getting image $($Name), $($Id) language metadata`n"

      $Result = Invoke-UupDumpApi listlangs @{ id = $Id }

      Write-Verbose "Get-UupDumpIso: Got $($Name) $($Id) language metadata:"
      Write-Verbose ($Result.Response | ConvertTo-Json -Depth 99) # pretty format as json
      Write-Verbose "`n"

      if ($Result.Response.updateinfo.build -ne $_.value.build) {
        throw 'Get-UupDumpIso: Unexpected build mismatch in listlangs'
      }

      Write-Host "Get-UupDumpIso: OK! No build mismatch in $($Name), $($Id) language metadata. Updating object.`n"

      # add language and update info to the response we are processing
      $_.value | Add-Member -NotePropertyMembers @{
        langs = $Result.Response.langFancyNames
        info = $Result.Response.updateInfo
      }

      Write-Verbose "Get-UupDumpIso: Languages retrieved for image $($Name) ($($Id)):"
      Write-Verbose ($_.value.langs | ConvertTo-Json -Depth 99) # pretty format as json
      Write-Verbose "`n"

      $Langs = $_.value.langs.PSObject.Properties.Name

      # get edition metadata

      $Editions = if ($langs -contains 'en-us') {

        Write-Host "Get-UupDumpIso: Getting $($Name) (ID: $($Id)) editions metadata.`n"

        $Result = Invoke-UupDumpApi -Name listeditions -Body @{ id = $Id; lang = 'en-us' }

        $Result.Response.editionFancyNames

      } else {

        Write-Host "Get-UupDumpIso: Skipping. Missing en-us language.`n"
        
        [PSCustomObject]@{}

      }

      Write-Verbose "Get-UupDumpIso: Retrieved editions:"
      Write-Verbose ($Editions | ConvertTo-Json -Depth 99)
      Write-Verbose "`n"

      $_.value | Add-Member -NotePropertyMembers @{ editions = $Editions }
      
      $_

  } `
  | Where-Object { # verify that ring, language, and editions are what we want

    Write-Host "Get-UupDumpIso: Verifying ring, langs and editions.`n"

    $Ring = $_.value.info.Ring
    $Langs = $_.value.langs.PSObject.Properties.Name
    $Editions = $_.value.editions.PSObject.Properties.Name

    # use $Target.PSObject.Properties['Ring'] rather than $Target.Ring
    # to check existence so it does not throw an error
    $ExpectedRing = if ($Target.PSObject.Properties['Ring']) { $Target.Ring } else { 'RETAIL' }

    Write-Host @"
Image ring: $($Ring)
Expected ring: $($ExpectedRing)

Image langs: $($Langs)
Desired lang: $('en-us')

Image edition(s): $($Editions)
Target edition(s): $($Target.Edition)

"@

    ($Ring -eq $ExpectedRing) -and
    ($Langs -contains 'en-us') -and # TODO: remove hardcoded en-us lang
    ($Editions -contains $Target.Edition)

    Write-Host "Get-UupDumpIso: Ring, langs, and editions are OK! Continuing.`n"

  } `
  | Select-Object -First 1 `
  | ForEach-Object {

    # these variables will be used in ApiUris below
    $Id = $_.value.uuid
    $Edition = $Target.Edition

    Write-Host "Get-UupDumpIso: OK! Returning final ISO parameters.`n"
    
    # return object
    [PSCustomObject]@{
      Name = $Name
      Title = $_.value.title
      Build = $_.value.build
      Id = $Id
      Edition = $Target.Edition
      VirtualEdition = if ($Target.PSObject.Properties['VirtualEdition']) { $Target.VirtualEdition } else { $null }
      # compose queries for requested version
      ApiUri = 'https://api.uupdump.net/get.php?' + (New-QueryString @{
        'id' = $Id
        'lang' = 'en-us'
        'edition' = $Edition
      })
      DownloadUri = 'https://uupdump.net/download.php?' + (New-QueryString @{
        'id' = $Id
        'pack' = 'en-us'
        'edition' = $Edition
      })
      DownloadPackageUri = 'https://uupdump.net/get.php?' + (New-QueryString @{
        'id' = $Id
        'pack' = 'en-us'
        'edition' = $Edition
      })
    } 
  }
}

function Get-IsoWindowsImages($IsoPath) {

  $IsoPath = Resolve-Path $IsoPath

  Write-Host "Get-IsoWindowsImages: Mounting $($IsoPath)"

  $IsoImage = Mount-DiskImage $IsoPath -PassThru

  try {

    $IsoVolume = $IsoImage | Get-Volume
    $InstallPath = "$($IsoVolume.DriveLetter):\sources\install.wim"

    Write-Host "Get-IsoWindowsImages: Getting Windows images from $($InstallPath)"

    Get-WindowsImage -ImagePath $InstallPath | ForEach-Object {

      $Image = Get-WindowsImage -ImagePath $InstallPath -Index $_.ImageIndex

      [PSCustomObject]@{
        Index = $Image.ImageIndex
        Name = $Image.ImageName
        Version = $Image.Version
      }

    }

  } finally {

    Write-Host "Get-IsoWindowsImages: Dismounting $($IsoPath)"

    Dismount-DiskImage $IsoPath | Out-Null

  }

}

function Get-WindowsIso([string]$Name, [hashtable]$Target, $Path) {

  $Iso = Get-UupDumpIso -Name $Name -Target $Target

  # log iso parameters to console
  Write-Host 'Get-WindowsIso: Get-UupDumpIso returned object:'
  Write-Host ($Iso | ConvertTo-Json -Depth 99) # pretty format as json
  Write-Host

  if ($Iso.Build -notmatch '^\d+\.\d+$') {
    throw "Get-WindowsIso: unexpected $($Name) build: $($Iso.Build)"
  }

  # create the build directory. Cannot have spaces in the PATH, so strip them from the Name.
  $BuildDirectory = (Join-Path -Path $Path -ChildPath ($Name -replace '\s',''))
  $DestinationIsoPath = "$($BuildDirectory).iso"
  $DestinationIsoMetadataPath = "$($DestinationIsoPath).json"
  $DestinationIsoChecksumPath = "$($DestinationIsoPath).sha256.txt"

  if (Test-Path $BuildDirectory) {
      Remove-Item -Force -Recurse $BuildDirectory | Out-Null
  }

  New-Item -ItemType Directory -Force $BuildDirectory | Out-Null

  # get the uupdump build package
  $Title = "$($Name) $($Iso.Edition) $($Iso.Build)"
  Write-Host "Get-WindowsIso: Downloading UUP dump package for $($Title).`n"

  $DownloadPackageBody = @{
    autodl = 2
    updates = 1
    cleanup = 1
  }

  Invoke-WebRequest `
    -Method Post `
    -Uri $Iso.DownloadPackageUri `
    -Body $DownloadPackageBody `
    -OutFile "$BuildDirectory.zip" |
    Out-Null
  
  # extract downloaded uupdump zip for image
  Expand-Archive `
    -Path "$BuildDirectory.zip" `
    -DestinationPath $BuildDirectory

  # populate the config file for uup build job
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

  Write-Host "Get-WindowsIso: Creating ISO for $($Title).`n"

  Push-Location $BuildDirectory

  Write-Host "Get-WindowsIso: Handing off to uup_download_windows.cmd.`n"
  # run uupdump script inline
  powershell cmd /c uup_download_windows.cmd | Out-String -Stream

  if ($LASTEXITCODE) {
    throw "Get-WindowsIso: uup_download_windows.cmd failed with exit code $($LASTEXITCODE)!"
  }

  Pop-Location

  $SourceIsoPath = Resolve-Path $BuildDirectory/*.Iso

  $IsoChecksum = (Get-FileHash -Algorithm SHA256 $SourceIsoPath).Hash.ToLowerInvariant()

  Set-Content -Encoding ascii -NoNewline -Path $DestinationIsoChecksumPath -Value $IsoChecksum

  $WindowsImages = Get-IsoWindowsImages $SourceIsoPath

  Set-Content -Path $DestinationIsoMetadataPath -value (
    ([PSCustomObject]@{
      name = $Name
      title = $Iso.Title
      build = $Iso.Build
      checksum = $IsoChecksum
      images = @($WindowsImages)
      uupDump = @{
        id = $Iso.Id
        apiUri = $Iso.ApiUri
        downloadUri = $Iso.DownloadUri
        downloadPackageUri = $Iso.DownloadPackageUri
      }
    } | ConvertTo-Json -Depth 99) -replace '\\u0026','&'
  )

  Write-Host "Get-WindowsIso: Moving ISO to $($DestinationIsoPath).`n"

  Move-Item -Force -Path $SourceIsoPath -Destination $DestinationIsoPath

  Write-Host 'Get-WindowsIso: All Done.'

}

Start-Transcript `
  -Path "job-$(Get-Date -UFormat %s).log"

Write-Host "uup-dump-get-windows-iso: Beginning execution: version $(git rev-parse --short HEAD) at $(Get-Date -UFormat %s)."

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Get-WindowsIso -Name $Version -Target $TARGETS[$Version] -Path $Path

$Stopwatch.Stop()

Write-Host "uup-dump-get-windows-iso: Execution completed at: $(Get-Date -UFormat %s), elapsed: $($Stopwatch.Elapsed.TotalSeconds) seconds."

Stop-Transcript