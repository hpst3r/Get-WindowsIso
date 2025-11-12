$ConfigFile = 'C:\build\new\get-windowsiso\config.json'
$BuildScript = 'C:\build\new\get-windowsiso\uup-dump-get-windows-iso.ps1'
$Config = (Get-Content $ConfigFile | ConvertFrom-Json)

Remove-Item $Config.WorkingDirectory -Force -Recurse
New-Item $Config.WorkingDirectory -Force -ItemType Directory

$Processes = foreach ($WindowsVersion in $Config.Versions) {

  Write-Host "stub: Starting script $($BuildScript) for version $($WindowsVersion) with working directory $($Config.WorkingDirectory)."

  Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $BuildScript, "-Version", "`"$WindowsVersion`"", "-Path", "`"$($Config.WorkingDirectory)`"", "-Verbose" `
    -PassThru

  Write-Host "stub: Waiting 60 seconds to avoid API rate limit."

  Start-Sleep -Seconds 60
  
}

Write-Host 'stub: Processes launched. Waiting for completion.'

foreach ($Process in $Processes) {

  $Process.WaitForExit()

}

Write-Host 'stub: Build processes finished.'

Write-Host 'stub: Beginning cleanup.'

New-Item $Config.OutputDirectory -Force -ItemType Directory

Write-Host "stub: Moving products to $($Config.OutputDirectory)."

Get-ChildItem $Config.WorkingDirectory |
  Where-Object Name -match "(sha256|.iso$)" |
  Move-Item -Destination $Config.OutputDirectory -Force

Write-Host "stub: Removing working directory $($Config.WorkingDirectory)."

Remove-Item $Config.WorkingDirectory -Force -Recurse

Write-Host 'stub: Done!'
