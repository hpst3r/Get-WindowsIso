# uup-dump-get-windows-iso.ps1

## Usage

Call the script from an elevated PowerShell session with a specified `-Version`:

```PowerShell
.\uup-dump-get-windows-iso.ps1 -Version 'Windows Server 2025 Datacenter (Core)'
```

## Environment

The only external dependency is Git, which may be installed with Winget (available out of the box in Windows 11 24H2, Server 2025 w/ DE: `winget install Git.Git`) or your preferred package manager (e.g. `scoop` or `choco`).

If you're running Windows Server 2025 with a desktop environment,
you can open up an elevated PowerShell terminal and:

```PowerShell
# install dependency: Git
winget install Git.Git --accept-source-agreements --disable-interactivity

# reload PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# create and move to working directory
$BuildLocation = (New-Item -ItemType Directory -Path "$($env:TEMP)\winbuild-$(Get-Date -UFormat %s))"
Push-Location $BuildLocation

# clone the repository
git clone https://github.com/hpst3r/Get-WindowsISO

# run the script
.\Get-WindowsISO\uup-dump-get-windows-iso.ps1 -Version 'Windows Server 2025 Datacenter (Core)'
```

## Inputs

The `-Version` parameter requires a target Windows edition, one of:

- 'Windows 11 Professional, version 23H2'
- 'Windows 11 Enterprise, version 23H2'
- 'Windows 11 Professional, version 24H2'
- 'Windows 11 Enterprise, version 24H2'
- 'Windows Server 2025'
- 'Windows Server 2025 Datacenter'
- 'Windows Server 2025 Datacenter (Core)'
- 'Windows Server 2025 Standard'
- 'Windows Server 2025 Standard (Core)'
- 'Windows Server 2022'
- 'Windows Server 2022 Datacenter'
- 'Windows Server 2022 Datacenter (Core)'
- 'Windows Server 2022 Standard'
- 'Windows Server 2022 Standard (Core)'

## Outputs

The script produces a Windows ISO of the requested version, edition and
virtual edition (e.g. Education or Enterprise). For options, see the
`$TARGETS` hashtable.
