# uup-dump-get-windows-iso.ps1

## Usage

Call the script from an elevated PowerShell session with a specified `-Version`:

```PowerShell
.\uup-dump-get-windows-iso.ps1 -Version 'Windows Server 2025 Datacenter (Core)'
```

## Environment

The only external dependency is Git, which may be installed with Winget
(available out of the box in Windows 11 24H2, Server 2025 w/ DE:
`winget install Git.Git`) or your preferred package manager
(e.g. `scoop` or `choco`).

A build requires approximately 4 GB of memory (not including OS overhead)
and can realistically utilize 4 vCPUs. There is *some* multithreaded
compression, but the lengthy parts of the job are during `dism` operations,
and `dism` is singlethreaded.

To set up a Windows Server 2025 installation (with desktop environment),
you can open up an elevated PowerShell terminal and:

```PowerShell
# install dependency: Git
winget install Git.Git --accept-source-agreements --disable-interactivity

# reload PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# create and move to working directory
$BuildLocation = (New-Item -ItemType Directory -Path "$($env:TEMP)\winbuild-$(Get-Date -UFormat %s)")
Push-Location $BuildLocation

# clone the repository
git clone https://github.com/hpst3r/Get-WindowsISO

# run the script
.\Get-WindowsISO\uup-dump-get-windows-iso.ps1 -Version 'Windows Server 2025 Datacenter (Core)'
```

Windows 11, version 24H2 (and newer) should also work without trouble.

If you're using Server Core, you will, need to install a package manager
or get Git another way. I have not tested this on Server Core;
there may be other pitfalls.

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
