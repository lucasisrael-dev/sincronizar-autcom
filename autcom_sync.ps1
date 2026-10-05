# ==============================================================================
# Script de Sincronização: X:\autcom (Samba Linux) -> C:\autcom
# ==============================================================================

# Ajusta codificação do console para UTF-8 (evita acentuação corrompida)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$Source = "X:\autcom"
$Destination = "C:\autcom"

# Verifica se a origem está acessível
if (-not (Test-Path $Source)) {
    Write-Host "Erro: A pasta de origem '$Source' não foi encontrada ou o Samba está inacessível." -ForegroundColor Red
    exit
}

# Garantir que os diretórios existam no destino sem copiar seus arquivos
$EmptyDirsToEnsure = @(
    "PedidoOrcamento",
    "Boletos",
    "Docs_Env_Reimp"
)

foreach ($dir in $EmptyDirsToEnsure) {
    $targetPath = Join-Path $Destination $dir
    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }
}

# Diretórios a excluir do robocopy
# Comente o diretorio ifiscal e painelnfe da loja onde o script vai rodar
$ExcludeDirs = @(
    "$Source\exe",
    "$Source\Boletos",
    "$Source\PedidoOrcamento",
    "$Source\Docs_Env_Reimp",
    #"$Source\ifiscal_001",
    "$Source\ifiscal_002",
    "$Source\ifiscal_003",
    "$Source\ifiscal_004",
    #"$Source\ifiscal_005",
    "$Source\ifiscal_006",
    #"$Source\ifiscal_007",
    #"$Source\ifiscal_008",
    #"$Source\ifiscal_009",
    "$Source\ifiscal_010",
    "$Source\ifiscal_011",
    "$Source\ifiscal_012",
    "$Source\ifiscal_013",
    "$Source\ifiscal_014",
    "$Source\ifiscal_101",
    "$Source\ifiscal_102",
    "$Source\ifiscal_103",
    "$Source\ifiscal_201",
    "$Source\ifiscal_301",
    #"$Source\painelnfe_001",
    "$Source\painelnfe_002",
    "$Source\painelnfe_003",
    "$Source\painelnfe_004",
    #"$Source\painelnfe_005",
    "$Source\painelnfe_006",
    #"$Source\painelnfe_007",
    #"$Source\painelnfe_008",
    #"$Source\painelnfe_009",
    "$Source\painelnfe_010",
    "$Source\painelnfe_011",
    "$Source\painelnfe_012",
    "$Source\painelnfe_013",
    "$Source\painelnfe_014",
    "$Source\painelnfe_101",
    "$Source\painelnfe_102",
    "$Source\painelnfe_103",
    "$Source\painelnfe_201",
    "$Source\painelnfe_301"
)

# Extensões de arquivos a excluir
$ExcludeFiles = @(
    "*.ee*",
    "*.cop*",
    "*.old*"
)

# Argumentos base do Robocopy
$BaseArgs = @(
    "`"$Source`"",
    "`"$Destination`"",
    "/E",
    "/FFT",
    "/DCOPY:DAT",
    "/COPY:DAT",
    "/PURGE",
    "/R:2",
    "/W:2"
)

if ($ExcludeDirs.Count -gt 0) {
    $BaseArgs += "/XD"
    $BaseArgs += $ExcludeDirs | ForEach-Object { "`"$_`"" }
}

if ($ExcludeFiles.Count -gt 0) {
    $BaseArgs += "/XF"
    $BaseArgs += $ExcludeFiles | ForEach-Object { "`"$_`"" }
}

# ------------------------------------------------------------------------------
# 1. FASE DE ANÁLISE (Pré-escaneamento em modo /L)
# ------------------------------------------------------------------------------
Write-Host "Analisando arquivos e calculando diferenças com o Samba..." -ForegroundColor Cyan

# Flags para varredura silenciosa que retorne apenas a lista de arquivos afetados
$DryRunArgs = $BaseArgs + @("/L", "/NJH", "/NJS", "/NDL", "/NC", "/NS", "/NP")

# Executa o robocopy apenas em simulação e ignora linhas de erro do log
$filesToProcess = & robocopy.exe $DryRunArgs | Where-Object { $_ -match '\S' -and $_ -notmatch 'ERROR' }
$totalFiles = $filesToProcess.Count

if ($totalFiles -eq 0) {
    Write-Host "A pasta destino já está exatamente idêntica à origem. Nenhum arquivo para copiar!" -ForegroundColor Green
    exit
}

Write-Host "Total de arquivos pendentes para cópia/sincronização: $totalFiles" -ForegroundColor Yellow
Write-Host "Iniciando cópia...`n" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 2. FASE DE CÓPIA EM TEMPO REAL (Linha única no terminal)
# ------------------------------------------------------------------------------
$CopyArgs =$BaseArgs + @("/NJH", "/NJS", "/NDL", "/NC", "/NS", "/NP")

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$currentCount = 0

# Configura o processo para capturar a saída em tempo real
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = "robocopy.exe"
$pinfo.Arguments = ($CopyArgs -join " ")
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false
$pinfo.CreateNoWindow = $true
$pinfo.StandardOutputEncoding = [System.Text.Encoding]::Default

$process = [System.Diagnostics.Process]::Start($pinfo)

# Largura do terminal para formatação da linha
try { $windowWidth = $Host.UI.RawUI.WindowSize.Width } catch {$windowWidth = 80 }
if (-not $windowWidth -or $windowWidth -lt 20) {$windowWidth = 80 }

while (-not $process.StandardOutput.EndOfStream) {
    $line =$process.StandardOutput.ReadLine()
    if ([string]::IsNullOrWhiteSpace($line) -or$line -match 'ERROR') { continue }

    $currentCount++
    $elapsed =$sw.Elapsed

    # Cálculo da Média e Estimativa de Tempo Restante (ETA)
    $avgSecondsPerFile = $elapsed.TotalSeconds / $currentCount
    $remainingFiles = $totalFiles - $currentCount
    $etaSeconds = [math]::Max(0, $remainingFiles * $avgSecondsPerFile)
    $etaTimeSpan = [TimeSpan]::FromSeconds($etaSeconds)

    $etaStr = if ($etaTimeSpan.TotalHours -ge 1) { $etaTimeSpan.ToString("hh\:mm\:ss") } else { $etaTimeSpan.ToString("mm\:ss") }
    $percent = [math]::Round(($currentCount / $totalFiles) * 100, 1)

    # Extrai o nome do arquivo
    $fileNameOnly = Split-Path $line.Trim() -Leaf
    if ([string]::IsNullOrEmpty($fileNameOnly)) { $fileNameOnly =$line.Trim() }

    # Monta a linha de status
    $statusText = "[$currentCount/$totalFiles]$percent% | ETA: $etaStr \vert{} Copiando: $fileNameOnly"

    # Trunca caso ultrapasse a largura da janela para impedir quebras automáticas de linha
    if ($statusText.Length -ge $windowWidth) {$statusText = $statusText.Substring(0,$windowWidth - 4) + "..."
    }

    # Preenche com espaços em branco para apagar caracteres sobressalentes da linha anterior
    $statusText = $statusText.PadRight($windowWidth - 1)

    # Reescreve no mesmo ponto no console usando o caractere Carriage Return (`r)
    Write-Host "`r$statusText" -NoNewline
}

$process.WaitForExit()
$sw.Stop()

# ------------------------------------------------------------------------------
# 3. FINALIZAÇÃO
# ------------------------------------------------------------------------------
$totalTimeFormatted = if ($sw.Elapsed.TotalHours -ge 1) { $sw.Elapsed.ToString("hh\:mm\:ss") } else { $sw.Elapsed.ToString("mm\:ss") }

# Limpa a linha do progresso
Write-Host ("`r" + (" " * ($windowWidth - 1)) + "`r") -NoNewline
Write-Host "Sincronização concluída com sucesso!" -ForegroundColor Green
Write-Host "Arquivos processados : $currentCount de $totalFiles" -ForegroundColor White
Write-Host "Tempo total decorrido: $totalTimeFormatted" -ForegroundColor White