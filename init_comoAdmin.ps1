#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath 'C:\autcom' -PathType Container)) {
    New-Item -ItemType Directory -Path 'C:\autcom' -ErrorAction Stop | Out-Null
}

icacls 'C:\autcom' /grant '*S-1-5-32-545:(OI)(CI)M'
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to grant Modify permissions to the built-in Users group on C:\autcom.'
}