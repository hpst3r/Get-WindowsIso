$Username = "ImageWorker"
$Password = "UseAStrongPasswordHere123!"
$UserDesc = "Local account for scheduled DISM task"

# create user
if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
    New-LocalUser `
        -Name $Username `
        -Password ($Password | ConvertTo-SecureString -AsPlainText -Force) `
        -FullName "Image Task User" `
        -Description $UserDesc `
        -PasswordNeverExpires:$true
    Write-Host "Created user '$Username'"
} else {
    Write-Host "User '$Username' already exists"
}
Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction SilentlyContinue

# grant SeBatchLogonRight (log on as batch job)
# remove SeInteractiveLogonRight
# use mmc, scripting this is a pain

$TaskParameters = @(
    '/Create',
    '/TN', 'WeeklyImageUpdate',
    '/RU', $Username,
    '/RP', $Password,
    '/SC', 'WEEKLY',
    '/D', 'WED',
    '/ST', '00:00',
    '/RL', 'HIGHEST',
    '/TR', '"powershell.exe -ExecutionPolicy Bypass -File D:\Get-WindowsIso\stub.ps1"'
)

Start-Process -FilePath 'schtasks.exe' -ArgumentList $TaskParameters -Wait -NoNewWindow
