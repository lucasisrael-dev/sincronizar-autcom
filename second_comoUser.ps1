[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Ensure X: points to the required network share.
$targetShare = '\\172.16.0.11\c_linux'
$xDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = 'X:'" -ErrorAction Stop
$currentShare = if ($xDrive) { $xDrive.ProviderName } else { $null }

if ($currentShare -and $currentShare.TrimEnd('\') -ieq $targetShare.TrimEnd('\')) {
    Write-Output 'X: is already mapped to the expected share.'
}
else {
    if ($xDrive) {
        if (-not $currentShare) {
            throw 'X: already exists and is not a mapped network drive; it was not changed.'
        }

        & net.exe use X: /delete /y
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to remove the existing X: mapping to '$currentShare'."
        }
    }

    & net.exe use X: $targetShare /persistent:yes
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to map X: to '$targetShare'."
    }
}

# Create application shortcuts on the current user's Desktop if they are missing.
$desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
$shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
$shortcuts = @(
    @{ Name = 'C_Autcom'; Target = 'C:\autcom\autcom.exe' },
    @{ Name = 'C_Painelnfe'; Target = 'C:\autcom\painelnfe_001\PainelNFe.exe' }
)

foreach ($item in $shortcuts) {
    $shortcutPath = Join-Path -Path $desktopPath -ChildPath "$($item.Name).lnk"
    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $item.Target
        $shortcut.WorkingDirectory = Split-Path -Path $item.Target -Parent
        $shortcut.Save()
    }
}
