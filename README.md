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
- 'Windows 11 Professional, version 25H2'
- 'Windows 11 Enterprise, version 25H2'
- 'Windows 11 Professional, version 26H2'
- 'Windows 11 Enterprise, version 26H2'
- 'Windows 11 Professional, Insider Preview 29xxx' (always the latest 29xxx Insider build)
- 'Windows 11 Enterprise, Insider Preview 29xxx'
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

## Building several versions (`stub.ps1`)

`stub.ps1` builds every version in `config.json` and moves each finished ISO (with its
`.iso.json` and `.iso.sha256.txt`) to `OutputDirectory`:

- Builds run **one at a time** (`MaxParallel`, default 1). uupdump's converter always mounts
  at `<drive>:\MountUUP` and uses `<drive>:\W10UIuup` as scratch, so parallel conversions on
  the same drive corrupt each other.
- A version whose published ISO is already the latest build (same uupdump id) is skipped
  without downloading anything. Pass `-Force` to rebuild anyway.
- Only builds that exit successfully are published, so a failed build never replaces the
  previous ISO. A build running longer than `TimeoutHoursPerVersion` (default 4) is killed.
- Stale converter mounts from a killed run are cleaned up at the start of the next one.
- Exit code is non-zero if any version failed.

Logs are written to `logs\` next to the scripts: `stub-*.log`, `Get-Iso-*.log` per version,
and `Convert-*.log` with the raw uupdump download/converter output (written live).

Each run also writes a machine-readable summary, `logs\last-run-stub.json` (plus a
`stub-<timestamp>.json` copy beside the transcript): start/end time, exit code, log file,
and per version the status (`Published`, `UpToDate`, `Failed`), minutes, the published
build and, for a new build, the build it replaced. Customize-WindowsIso's
`Send-BuildNotification.ps1` reads it.

To run it weekly, see `scheduled-task.ps1`. If you also use
[Customize-WindowsIso](https://github.com/hpst3r/Customize-WindowsIso), use its
`register-task.ps1` instead: one task runs both stages in order.

## Outputs

The script produces a Windows ISO of the requested version, edition and
virtual edition (e.g. Education or Enterprise). For options, see the
`$TARGETS` hashtable.
