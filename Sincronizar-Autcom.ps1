<#
.SYNOPSIS
    Sincroniza X:\autcom com C:\Autcom para lojas do sistema Autcom.
.PARAMETER CodigoLoja
    Código de 3 dígitos da loja (ex: 001, 002, 101, 301, etc.)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Informe o código da loja")]
    [ValidateSet('001','002','003','004','005','007','008','009','010','011','012','013','014','101','102','103','201','301')]
    [string]$CodigoLoja,

    [switch]$AdminPhase
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# -----------------------------------------------------------------------------
# FUNÇÃO AUXILIAR: TESTA SE O PROCESSO ATUAL TEM PRIVILÉGIOS DE ADMINISTRADOR
# -----------------------------------------------------------------------------
function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# -----------------------------------------------------------------------------
# FASE ADMINISTRATIVA (Criação de C:\Autcom e Permissões Globais)
# Executada via elevação UAC
# -----------------------------------------------------------------------------
if ($AdminPhase) {
    if (-not (Test-IsAdmin)) {
        Write-Error "Fase administrativa chamada sem privilégios elevadados."
        exit 1
    }

    $cPath = "C:\Autcom"

    if (-not (Test-Path -Path $cPath)) {
        Write-Host "Criando diretório $cPath..." -ForegroundColor Green
        New-Item -Path $cPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Configurando permissões do Windows Users (SID S-1-5-32-545)..." -ForegroundColor Green
    
    # Identificador Universal do Grupo de Usuários do Windows (BUILTIN\Users)
    $sidUsers = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    
    $acl = Get-Acl -Path $cPath
    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
    $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
    $accessControlType = [System.Security.AccessControl.AccessControlType]::Allow

    # Concede permissão de controle total (FullControl) aos usuários locais
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidUsers,
        "FullControl",
        $inheritanceFlags,
        $propagationFlags,
        $accessControlType
    )

    $acl.AddAccessRule($rule)
    Set-Acl -Path $cPath -AclObject $acl

    # Garante que as pastas locais de controle existam
    $localFolders = @("Boletos", "exe", "DANFE", "Docs_Env_Reimp", "PedidoOrcamento")
    foreach ($folder in $localFolders) {
        $subFolder = Join-Path -Path $cPath -ChildPath $folder
        if (-not (Test-Path -Path $subFolder)) {
            New-Item -Path $subFolder -ItemType Directory -Force | Out-Null
        }
    }

    Write-Host "Fase administrativa concluída com sucesso." -ForegroundColor Green
    exit 0
}

# -----------------------------------------------------------------------------
# MAPEAMENTO DE IPS POR CÓDIGO DE LOJA
# -----------------------------------------------------------------------------
$IpMap = @{
    '001' = '172.16.0.11'
    '002' = '192.168.2.253'
    '003' = '192.168.3.253'
    '004' = '192.168.4.253'
    '005' = '192.168.5.253'
    '007' = '192.168.7.253'
    '008' = '192.168.8.253'
    '009' = '192.168.9.253'
    '010' = '192.168.10.253'
    '011' = '192.168.11.253'
    '012' = '192.168.12.253'
    '013' = '192.168.13.253'
    '014' = '192.168.14.253'
    '101' = '192.168.101.253'
    '102' = '192.168.102.253'
    '103' = '192.168.103.253'
    '201' = '192.168.201.253'
    '301' = '192.168.231.253'
}

$lojaIp = $IpMap[$CodigoLoja]
$uncPath = "\\$lojaIp\c_linux"

# -----------------------------------------------------------------------------
# TAREFA 1: ELEVAÇÃO PARA VERIFICAR/CRIAR C:\Autcom E CONCEDER PERMISSÕES
# -----------------------------------------------------------------------------
$cPath = "C:\Autcom"
Write-Host "[Tarefa 1/4] Verificando a pasta $cPath..." -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $cPath -PathType Container)) {
    Write-Host "A pasta C:\Autcom não existe. Solicitando autorização de administrador..." -ForegroundColor Yellow
    
    # Chama o próprio script em modo elevado apenas para a criação/permissão do diretório
    $scriptPath = $MyInvocation.MyCommand.Path
    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -CodigoLoja $CodigoLoja -AdminPhase"
    
    if ($process.ExitCode -ne 0) {
        Write-Error "A elevação de privilégios falhou ou foi cancelada pelo usuário. O script não pode continuar."
        exit 1
    }

    Write-Host "[Tarefa 1/4] Concluída: pasta criada e permissões configuradas." -ForegroundColor Green
}
else {
    Write-Host "[Tarefa 1/4] Nenhuma ação necessária: a pasta já existe." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# TAREFA 2: VERIFICAR/CRIAR MAPEAMENTO X: NO CONTEXTO DO USUÁRIO LOGADO
# -----------------------------------------------------------------------------
Write-Host "[Tarefa 2/4] Verificando o mapeamento da unidade X:..." -ForegroundColor Cyan

$diskX = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='X:'" -ErrorAction SilentlyContinue
$currentProvider = if ($diskX) { $diskX.ProviderName } else { $null }
$normalizedProvider = if ($currentProvider) { $currentProvider.TrimEnd('\') } else { $null }
$normalizedTarget = $uncPath.TrimEnd('\')

if ($normalizedProvider -and $normalizedProvider -ieq $normalizedTarget) {
    Write-Host "[Tarefa 2/4] Nenhuma ação necessária: X: já está mapeada para $uncPath." -ForegroundColor Green
}
else {
    if ($diskX) {
        if (-not $currentProvider) {
            Write-Error "A unidade X: já está em uso e não é um mapeamento de rede. O mapeamento não foi alterado."
            exit 1
        }

        Write-Host "Unidade X: está apontando para $currentProvider. Remapeando para $uncPath..." -ForegroundColor Yellow
        & net.exe use X: /delete /yes
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Não foi possível remover o mapeamento atual de X:."
            exit 1
        }
    }
    else {
        Write-Host "Mapeando X: para $uncPath..." -ForegroundColor Yellow
    }

    & net.exe use X: "$uncPath" /persistent:yes
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Não foi possível mapear X: para $uncPath."
        exit 1
    }

    $diskX = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='X:'" -ErrorAction Stop
    $currentProvider = if ($diskX) { $diskX.ProviderName } else { $null }
    if (-not $currentProvider -or $currentProvider.TrimEnd('\') -ine $normalizedTarget) {
        Write-Error "A unidade X: não foi mapeada corretamente para $uncPath."
        exit 1
    }

    Write-Host "[Tarefa 2/4] Concluída: X: foi mapeada para $uncPath." -ForegroundColor Green
}

# Garante que os atalhos dos aplicativos existam na Área de Trabalho do usuário atual
Write-Host "[Tarefa 3/4] Verificando os atalhos na Área de Trabalho..." -ForegroundColor Cyan
$desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$shortcutShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
$shortcuts = @(
    @{ Name = 'C_Autcom'; Target = 'C:\Autcom\autcom.exe' },
    @{ Name = 'X_Autcom'; Target = 'X:\Autcom\autcom.exe' },
    @{ Name = 'C_PainelNfe'; Target = "C:\autcom\painelnfe_$CodigoLoja\PainelNFe.exe" },
    @{ Name = 'X_PainelNfe'; Target = "X:\autcom\painelnfe_$CodigoLoja\PainelNFe.exe" }
)
$changedShortcuts = 0

foreach ($item in $shortcuts) {
    $shortcutPath = Join-Path -Path $desktopPath -ChildPath "$($item.Name).lnk"
    $shortcutExists = Test-Path -LiteralPath $shortcutPath
    $shortcut = $shortcutShell.CreateShortcut($shortcutPath)

    if (-not $shortcutExists -or $shortcut.TargetPath -ine $item.Target) {
        $shortcut.TargetPath = $item.Target
        $shortcut.WorkingDirectory = Split-Path -Path $item.Target -Parent
        $shortcut.Save()
        $changedShortcuts++
        $action = if ($shortcutExists) { 'corrigido' } else { 'criado' }
        Write-Host "Atalho ${action}: $shortcutPath" -ForegroundColor Green
    }
}

if ($changedShortcuts -eq 0) {
    Write-Host "[Tarefa 3/4] Nenhuma ação necessária: os quatro atalhos já existem." -ForegroundColor Green
}
else {
    Write-Host "[Tarefa 3/4] Concluída: $changedShortcuts atalho(s) criado(s) ou corrigido(s)." -ForegroundColor Green
}

# Garante que as pastas locais de controle existam na máquina do usuário
$localFolders = @("Boletos", "exe", "DANFE", "Docs_Env_Reimp", "PedidoOrcamento")
foreach ($folder in $localFolders) {
    $subFolder = "C:\Autcom\$folder"
    if (-not (Test-Path -Path $subFolder)) {
        New-Item -Path $subFolder -ItemType Directory -Force | Out-Null
    }
}

# -----------------------------------------------------------------------------
# TAREFA 4: SINCRONIZAÇÃO VIA ROBOCOPY
# -----------------------------------------------------------------------------
$origem = "X:\autcom"
$destino = "C:\Autcom"

Write-Host "[Tarefa 4/4] Verificando e sincronizando $origem para $destino..." -ForegroundColor Cyan

if (-not (Test-Path -Path $origem)) {
    Write-Error "Origem $origem não encontrada no compartilhamento Samba. Verifique a conexão de rede."
    exit 1
}

# Parâmetros de exclusão
$excludeDirs = @(
    "atualizador_tinta",
    "Boletos",
    "exe",
    "DANFE",
    "Docs_Env_Reimp",
    "PedidoOrcamento",
    "jre6*",
    "jre7*"
)

$excludeFiles = @(
    "*.cop*",
    "*.old*",
    "*.00*",
    "*.ee*"
)

# Execução do Robocopy
# /MIR  : Espelhamento completo (copia alterações e remove em C o que foi apagado em X)
# /FFT  : Tolerância de tempo de 2 segundos (essencial para Samba/Linux)
# /R:2  : Tenta 2 vezes em caso de falha de leitura
# /W:3  : Aguarda 3 segundos entre tentativas
$logName = 'Sincronizar-Autcom-Robocopy-{0:yyyyMMdd-HHmmss-fff}-{1}.log' -f (Get-Date), $PID
$robocopyLog = Join-Path -Path $env:TEMP -ChildPath $logName
$robocopyUnicodeLog = "$robocopyLog.unicode"
$robocopyArguments = @(
    $origem,
    $destino,
    '/MIR',
    '/FFT',
    '/R:2',
    '/W:3',
    '/XD'
) + $excludeDirs + @('/XF') + $excludeFiles + @('/TEE', "/UNILOG:$robocopyUnicodeLog")
$quotedArguments = $robocopyArguments | ForEach-Object { '"{0}"' -f $_ }

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = 'robocopy.exe'
$processInfo.Arguments = $quotedArguments -join ' '
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.StandardOutputEncoding = [System.Text.Encoding]::Default

$robocopyProcess = [System.Diagnostics.Process]::Start($processInfo)
$errorOutputStarted = $false
Write-Host 'Sincronizando arquivos...' -NoNewline

while (($outputLine = $robocopyProcess.StandardOutput.ReadLine()) -ne $null) {
    if ($outputLine -match '(?i)\b(?:ERROR|ERRO)\s+\d+') {
        if (-not $errorOutputStarted) {
            Write-Host ''
            $errorOutputStarted = $true
        }

        Write-Host $outputLine -ForegroundColor Red
    }
}

$robocopyProcess.WaitForExit()
$robocopyExitCode = $robocopyProcess.ExitCode
$robocopyProcess.Dispose()
Write-Host ''

$robocopyOutput = [System.IO.File]::ReadAllText($robocopyUnicodeLog, [System.Text.Encoding]::Unicode)
[System.IO.File]::WriteAllText($robocopyLog, $robocopyOutput, [System.Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $robocopyUnicodeLog -ErrorAction Stop

# Códigos de retorno do Robocopy até 7 indicam sucesso ou arquivos atualizados sem erro fatal
if ($robocopyExitCode -lt 8) {
    if ($robocopyExitCode -eq 0) {
        Write-Host "[Tarefa 4/4] Nenhuma ação necessária: origem e destino já estão sincronizados." -ForegroundColor Green
    }
    else {
        Write-Host "[Tarefa 4/4] Concluída sem falhas. Código de retorno Robocopy: $robocopyExitCode. Log: $robocopyLog" -ForegroundColor Green
    }
}
else {
    Write-Error "[Tarefa 4/4] Falha na sincronização. Código de retorno Robocopy: $robocopyExitCode. Consulte o log: $robocopyLog"
}