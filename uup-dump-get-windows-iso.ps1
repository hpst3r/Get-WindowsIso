#Requires -Version 5.1 -RunAsAdministrator

<#
.SYNOPSIS
Creates a Windows ISO via uupdump.

.INPUTS
[string]$Version:
  The target build/Editions of Windows - for example,
  "Windows 11 Professional, version 24H2" for Windows 11 Pro, version 24H2, or
  "Windows Server 2025 Datacenter (Core)" for Windows Server 2025 Datacenter Core.

  All options:

  'Windows 11 Professional, version 23H2'
  'Windows 11 Enterprise, version 23H2'

  'Windows 11 Professional, version 24H2'
  'Windows 11 Enterprise, version 24H2'

  'Windows 11 Professional, version 25H2'
  'Windows 11 Enterprise, version 25H2'

  'Windows 11 Professional, Preview 26220'
  'Windows 11 Enterprise, Preview 26220'

  'Windows Server 2025'
  'Windows Server 2025 Datacenter'
  'Windows Server 2025 Datacenter (Core)'
  'Windows Server 2025 Standard'
  'Windows Server 2025 Standard (Core)'

  'Windows Server 2022'
  'Windows Server 2022 Datacenter'
  'Windows Server 2022 Datacenter (Core)'
  'Windows Server 2022 Standard'
  'Windows Server 2022 Standard (Core)'

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
  [string]$Path = 'output'
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

trap {

  Write-Error $_

  @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1') | Write-Host

  @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1') | Write-Host

  exit 1

}

# the OS build targets available as options for the $Target parameter.
# To add a new option, you can test a search string on the uupdump.net main site's search page.
# Each target has a search string to be fed to the API, desired editions,
# and optionally virtual editions (e.g., Enterprise, Education, IoT) and ring (DEV, WIF, RETAIL, etc).
# TODO: retire Enterprise build. Switch editions after installing Pro if you want it.

[hashtable]$TARGETS = @{

  'Windows 11, version 23H2'               = @{
    Search   = 'Windows 11, version 23H2'
    Editions = @('core', 'professional')
  }
  'Windows 11 Professional, version 23H2'  = @{
    Search   = 'Windows 11, version 23H2'
    Editions = @('professional')
  }
  'Windows 11 Enterprise, version 23H2'    = @{
    Search          = 'Windows 11, version 23H2'
    Editions        = @('professional')
    VirtualEditions = @('enterprise')
  }
  'Windows 11, version 24H2'               = @{
    Search   = 'Windows 11, version 24H2'
    Editions = @('core', 'professional')
  }
  'Windows 11 Professional, version 24H2'  = @{
    Search   = 'Windows 11, version 24H2'
    Editions = @('professional')
  }
  'Windows 11 Enterprise, version 24H2'    = @{
    Search          = 'Windows 11, version 24H2'
    Editions        = @('professional')
    VirtualEditions = @('enterprise')
  }
  'Windows 11, version 25H2'               = @{
    Search          = 'Windows 11, version 25H2'
    Editions        = @('core', 'professional')
  }
  'Windows 11 Professional, version 25H2'  = @{
    Search   = 'Windows 11, version 25H2'
    Editions = @('professional')
  }
  'Windows 11 Enterprise, version 25H2'    = @{
    Search          = 'Windows 11, version 25H2'
    Editions        = @('professional')
    VirtualEditions = @('enterprise')
  }

  'Windows 11 Professional, Preview 26220' = @{
    Search   = 'Windows 11 Insider Preview 10.0.26220'
    Editions = @('professional')
    Ring     = 'DEV'
  }
  'Windows 11 Enterprise, Preview 26220'   = @{
    Search          = 'Windows 11 Insider Preview 10.0.26220'
    Editions        = @('professional')
    VirtualEditions = @('enterprise')
    Ring            = 'DEV'
  }
  'Windows Server 2025'                    = @{
    Search   = 'Windows Server 2025'
    Editions = @('serverdatacenter', 'serverdatacentercore', 'serverstandard', 'serverstandardcore')
  }
  'Windows Server 2025 Datacenter'         = @{
    Search   = 'Windows Server 2025'
    Editions = @('serverdatacenter')
  }
  'Windows Server 2025 Datacenter (Core)'  = @{
    Search   = 'Windows Server 2025'
    Editions = @('serverdatacentercore')
  }
  'Windows Server 2025 Standard'           = @{
    Search   = 'Windows Server 2025'
    Editions = @('serverstandard')
  }
  'Windows Server 2025 Standard (Core)'    = @{
    Search   = 'Windows Server 2025'
    Editions = @('serverstandardcore')
  }
  'Windows Server 2022'                    = @{
    Search   = 'Microsoft server operating system, version 21H2'
    Editions = @('serverdatacenter', 'serverdatacentercore', 'serverstandard', 'serverstandardcore')
  }
  'Windows Server 2022 Datacenter'         = @{
    Search   = 'Microsoft server operating system, version 21H2'
    Editions = @('serverdatacenter')
  }
  'Windows Server 2022 Datacenter (Core)'  = @{
    Search   = 'Microsoft server operating system, version 21H2'
    Editions = @('serverdatacentercore')
  }
  'Windows Server 2022 Standard'           = @{
    Search   = 'Microsoft server operating system, version 21H2'
    Editions = @('serverstandard')
  }
  'Windows Server 2022 Standard (Core)'    = @{
    Search   = 'Microsoft server operating system, version 21H2'
    Editions = @('serverstandardcore')
  }

}

<#
.SYNOPSIS
Wrapper to convert a hashtable of parameters to a url encoded string.
#>
function New-QueryString {
  param (
    [Parameter(Mandatory = $true)]
    [hashtable]$Parameters,
    [Parameter()]
    [int]$Attempts = 0
  )

  try {

    @($Parameters.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.value))"
      }) -join '&'

  }
  catch {

    # if fn failed to find type, add the System.Web type and try again once
    if ($Attempts -lt 1 -and ($_.Exception.Message -eq 'Unable to find type [System.Web.HttpUtility].')) {

      Write-Warning "New-QueryString: Failed to find System.Web.HttpUtility: Attempting to add type and try again."
      Add-Type -AssemblyName System.Web
      
      New-QueryString -Parameters $Parameters -Attempts ($Attempts++)

    }
    else {

      throw "New-QueryString: Failed: $($_)"

    }
  }

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
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
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

    }
    catch {

      $Failure = $_

      Write-Warning "Invoke-UupDumpApi: Failed the uup-dump api $($Name) request: $($Failure)"

    }

  }

  throw "Invoke-UupDumpApi: Failed to make uup-dump api $($Name) request after $($n) attempts. Possible timeout or incorrect parameters."

}

<#
.SYNOPSIS
Gets metadata and download URIs for a Windows build meeting requested Target criteria from uupdump.net.
#>
function Get-UupDumpIso([string]$Name, [hashtable]$Target) {

  Write-Host "Get-UupDumpIso: Getting metadata for $($Name).`n"

  Write-Host "Get-UupDumpIso: Using query: $($Target.Search)`n"
  
  $Result = Invoke-UupDumpApi -Name 'listid' -Body @{ 'search' = $Target.Search }

  Write-Verbose "Get-UupDumpIso: listid query response:"
  Write-Verbose ($Result | ConvertTo-Json -Depth 99)
  Write-Verbose "`n"

  $Builds = $Result.Response.builds.PSObject.Properties

  # iterate through the retrieved builds, looking for the first one that matches the target criteria
  foreach ($Build in $Builds) {

    $Id = $Build.value.uuid
    $Title = $Build.value.title
    $BuildNumber = $Build.value.build

    Write-Host "Get-UupDumpIso: Found build: $($Title) ($($Id)), build $($BuildNumber)`n"

    # verify preview state is as expected

    $IsPreviewExpected = ($Target.Search -like '*preview*')

    if (-not $IsPreviewExpected -and $Title -like '*preview*') {
      Write-Host "Get-UupDumpIso: This image is a preview, which was not requested. Skipping.`n"
      continue
    }

    Write-Host "Get-UupDumpIso: OK! Preview state is as expected for $($Title) ($($Id)). Continuing.`n"

    # collect language metadata

    Write-Host "Get-UupDumpIso: Getting language and edition metadata for $($Title) ($($Id)).`n"

    $LangResult = Invoke-UupDumpApi listlangs @{ id = $Id }

    Write-Verbose "Get-UupDumpIso: Got $($Name) $($Id) language metadata:"
    Write-Verbose ($LangResult.Response | ConvertTo-Json -Depth 99) # pretty format as json
    Write-Verbose "`n"

    # confirm the build number matches the build we requested

    if ($LangResult.Response.updateinfo.build -ne $BuildNumber) {
      throw 'Get-UupDumpIso: Unexpected build mismatch in listlangs'
    }

    # for comparison, convert all languages to lower case

    $Languages = $LangResult.Response.langList | ForEach-Object { $_.ToLowerInvariant() }

    Write-Verbose "Get-UupDumpIso: Languages retrieved for $($Name) $($Id):"
    Write-Verbose ($Languages | ConvertTo-Json -Depth 99)
    Write-Verbose "`n"

    # get editions for the build
    Write-Host "Get-UupDumpIso: Getting $($Name) (ID: $($Id)) editions metadata.`n"

    $EditionResult = Invoke-UupDumpApi -Name listeditions -Body @{ id = $Id; lang = 'en-us' }

    Write-Verbose "Get-UupDumpIso: Editions retrieved for $($Name) $($Id):"
    Write-Verbose ($EditionResult.Response | ConvertTo-Json -Depth 99)
    Write-Verbose "`n"

    # for comparison, extract an array of available edition names in lower case
    $BuildEditions = $EditionResult.Response.editionFancyNames.PSObject.Properties.Name | ForEach-Object { $_.ToLowerInvariant() }

    Write-Host "Get-UupDumpIso: Verifying ring, langs and editions.`n"

    # if the build is missing the desired language, edition, or ring, skip it

    if ($Languages -notcontains 'en-us') {

      Write-Host "Get-UupDumpIso: Skipping. Build is missing en-us language.`n"
      
      continue

    }

    Write-Verbose "Get-UupDumpIso: BuildEditions: $($BuildEditions -join ', ')"
    Write-Verbose "Get-UupDumpIso: Target.Editions: $($Target.Editions -join ', ')"

    $EditionsPresent = $Target.Editions | Where-Object { $BuildEditions -contains $_ }

    if (-not [bool]$EditionsPresent) {

      Write-Host "Get-UupDumpIso: Skipping. Build is missing target editions $($Target.Editions -join ', ').`n"
      
      continue

    }

    if ($Target.PSObject.Properties['Ring']) {

      if ($Build.value.ring -ne $Target.Ring) {

        Write-Host "Get-UupDumpIso: Skipping. Expected ring $($Target.Ring). Got $($Build.value.ring).`n"
        
        continue

      }

      Write-Host "Get-UupDumpIso: Ring is OK! Continuing.`n"

    }

    Write-Host "Get-UupDumpIso: Ring, langs, and editions are OK! Continuing.`n"

    # return a PSCustomObject with the matching build's metadata and download URIs

    return [PSCustomObject]@{
      Name               = $Name
      Title              = $Title
      Build              = $BuildNumber
      Id                 = $Id
      Editions           = $Target.Editions
      VirtualEditions    = if ($Target.PSObject.Properties['VirtualEditions']) { $Target.VirtualEditions } else { $null }
      # compose queries for requested version
      ApiUri             = 'https://api.uupdump.net/get.php?' + (New-QueryString @{
          'id'      = $Id
          'lang'    = 'en-us'
          'edition' = ($Target.Editions -join ';')
        })
      DownloadUri        = 'https://uupdump.net/download.php?' + (New-QueryString @{
          'id'      = $Id
          'pack'    = 'en-us'
          'edition' = ($Target.Editions -join ';')
        })
      DownloadPackageUri = 'https://uupdump.net/get.php?' + (New-QueryString @{
          'id'      = $Id
          'pack'    = 'en-us'
          'edition' = ($Target.Editions -join ';')
        })
    }

  }

  throw "Get-UupDumpIso: Failed to find a suitable build for $($Name) with search $($Target.Search), editions $($Target.Editions -join ', '), and ring $($Target.Ring)."

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
        Index   = $Image.ImageIndex
        Name    = $Image.ImageName
        Version = $Image.Version
      }

    }

  }
  finally {

    Write-Host "Get-IsoWindowsImages: Dismounting $($IsoPath)"

    Dismount-DiskImage $IsoPath | Out-Null

  }

}

function Get-WindowsIso {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [hashtable]$Target,
    [Parameter()]
    [System.Object]$Path
  )

  $Iso = Get-UupDumpIso -Name $Name -Target $Target

  # log iso parameters to console
  Write-Verbose 'Get-WindowsIso: Get-UupDumpIso returned object:'
  Write-Verbose ($Iso | ConvertTo-Json -Depth 99) # pretty format as json
  Write-Verbose "`n"

  if ($Iso.Build -notmatch '^\d+\.\d+$') {
    throw "Get-WindowsIso: unexpected $($Name) build: $($Iso.Build)"
  }

  # create the build directory. Cannot have spaces in the PATH, so strip them from the Name.
  $BuildDirectory = (Join-Path -Path $Path -ChildPath ($Name -replace '\s', ''))
  $DestinationIsoPath = "$($BuildDirectory).iso"
  $DestinationIsoMetadataPath = "$($DestinationIsoPath).json"
  $DestinationIsoChecksumPath = "$($DestinationIsoPath).sha256.txt"

  if (Test-Path $BuildDirectory) {
    Remove-Item -Force -Recurse $BuildDirectory | Out-Null
  }

  New-Item -ItemType Directory -Force $BuildDirectory | Out-Null

  # get the uupdump build package
  $Title = "$($Name) $($Iso.Editions) $($Iso.Build)"

  Write-Host "Get-WindowsIso: Downloading UUP dump package for $($Title) (URI $($Iso.DownloadPackageUri)).`n"

  $DownloadPackageBody = @{
    'autodl'  = 2
    'updates' = 1
    'cleanup' = 1
  }

  # TODO: this works but is very lazy
  for ($i = 0; $i -lt 15; $i++) {
    try {
      
      Invoke-WebRequest `
        -Method Post `
        -Uri $Iso.DownloadPackageUri `
        -Body $DownloadPackageBody `
        -OutFile "$BuildDirectory.zip" |
      Out-Null

      $Success = $true
      break

    }
    catch {

      Write-Warning "Get-WindowsIso: API request to download package failed: $($_)."

      Write-Warning "Get-WindowsIso: Waiting 10 seconds, then retrying request."

      Start-Sleep -Seconds 10

    }
  }

  if (-not $Success) {

    throw "Get-WindowsIso: Failed to download UUP dump package."

  }

  Write-Host "Get-WindowsIso: Expanding downloaded build package $($BuildDirectory).zip.`n"
  
  # extract downloaded uupdump zip for image
  Expand-Archive `
    -Path "$($BuildDirectory).zip" `
    -DestinationPath $BuildDirectory

  # populate the config file for uupdump build job
  $ConvertConfig = (Get-Content $BuildDirectory/ConvertConfig.ini) `
    -replace '^(AutoExit\s*)=.*', '$1=1' `
    -replace '^(Cleanup\s*)=.*', '$1=1' `
    -replace '^(NetFx3\s*)=.*', '$1=1' `
    -replace '^(ResetBase\s*)=.*', '$1=0' ` # this will break update integration
    -replace '^(SkipWinRE\s*)=.*', '$1=1'

  Set-Content `
    -Encoding ascii `
    -Path (Join-Path -Path $BuildDirectory -ChildPath ConvertConfig.ini) `
    -Value $ConvertConfig

  Write-Host "Get-WindowsIso: Creating ISO for $($Title).`n"

  Push-Location $BuildDirectory

  Write-Host "Get-WindowsIso: Handing off to uup_download_windows.cmd.`n"
  
  # run uupdump download/build inline
  powershell cmd /c uup_download_windows.cmd | Out-String -Stream

  if ($LASTEXITCODE) {
    throw "Get-WindowsIso: uup_download_windows.cmd failed with exit code $($LASTEXITCODE)!"
  }

  Pop-Location

  $SourceIsoPath = Resolve-Path $BuildDirectory/*.Iso

  $IsoChecksum = (Get-FileHash -Algorithm SHA256 $SourceIsoPath).Hash.ToLowerInvariant()

  Set-Content -Encoding ascii -NoNewline -Path $DestinationIsoChecksumPath -Value $IsoChecksum

  # get images in the ISO for manifest

  Write-Host "Get-WindowsIso: Getting Windows images in $($SourceIsoPath).`n"

  $WindowsImages = Get-IsoWindowsImages $SourceIsoPath

  Write-Host "Get-WindowsIso: Creating ISO metadata file $($DestinationIsoMetadataPath).`n"

  Set-Content -Path $DestinationIsoMetadataPath -value (
    ([PSCustomObject]@{
      name     = $Name
      title    = $Iso.Title
      build    = $Iso.Build
      checksum = $IsoChecksum
      images   = @($WindowsImages)
      uupDump  = @{
        id                 = $Iso.Id
        apiUri             = $Iso.ApiUri
        downloadUri        = $Iso.DownloadUri
        downloadPackageUri = $Iso.DownloadPackageUri
      }
    } | ConvertTo-Json -Depth 99) -replace '\\u0026', '&'
  )

  Write-Host "Get-WindowsIso: Moving ISO to $($DestinationIsoPath).`n"

  Move-Item -Force -Path $SourceIsoPath -Destination $DestinationIsoPath

  Write-Host 'Get-WindowsIso: All Done.'

}

Start-Transcript -Path "Get-Iso-$($Version)-$(Get-Date -UFormat %s).log"

Write-Host "uup-dump-get-windows-iso: Beginning execution: version $(git rev-parse --short HEAD) at $(Get-Date -UFormat %s)."

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Get-WindowsIso -Name $Version -Target $TARGETS[$Version] -Path $Path

$Stopwatch.Stop()

Write-Host "uup-dump-get-windows-iso: Execution completed at: $(Get-Date -UFormat %s), elapsed: $($Stopwatch.Elapsed.TotalSeconds) seconds."

Stop-Transcript
