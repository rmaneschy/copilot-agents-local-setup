<#
.SYNOPSIS
Indexa repositórios Git individualmente percorrendo o workspace de forma recursiva.

.DESCRIPTION
Este script percorre o diretório do workspace de forma recursiva, identifica cada
repositório pela presença da pasta `.git` e invoca o codebase-memory-mcp para indexar
cada um individualmente. Essa abordagem garante que o knowledge graph seja construído
por repositório, respeitando os limites de cada projeto.

A varredura é inteligente:
- Ao encontrar um `.git`, indexa aquele diretório e NÃO desce em subdiretórios
  (evita indexar submodules como repositórios separados).
- Repositórios podem ser filtrados por padrão de nome (include/exclude).
- Suporta execução paralela para workspaces grandes.

.PARAMETER Path
Caminho raiz do workspace a ser percorrido. Padrão: $HOME\workspace.

.PARAMETER MaxDepth
Profundidade máxima de busca recursiva por repositórios. Padrão: 3.

.PARAMETER Force
Força re-indexação completa (ignora cache incremental) em todos os repositórios.

.PARAMETER Include
Padrão glob para incluir apenas repositórios cujo nome corresponda. Padrão: * (todos).

.PARAMETER Exclude
Padrão glob para excluir repositórios cujo nome corresponda. Padrão: nenhum.

.PARAMETER Parallel
Número de repositórios a indexar em paralelo. Padrão: 1 (sequencial).

.PARAMETER DryRun
Apenas lista os repositórios que seriam indexados, sem executar a indexação.

.EXAMPLE
.\index-workspace.ps1
# Percorre ~/workspace recursivamente e indexa cada repositório encontrado

.EXAMPLE
.\index-workspace.ps1 -Path "C:\projetos" -MaxDepth 2
# Percorre C:\projetos com profundidade máxima de 2 níveis

.EXAMPLE
.\index-workspace.ps1 -Include "ms-*" -Exclude "*-legacy"
# Indexa apenas repositórios que começam com "ms-" excluindo os que terminam com "-legacy"

.EXAMPLE
.\index-workspace.ps1 -Force -Parallel 4
# Re-indexação completa de todos os repos, 4 em paralelo

.EXAMPLE
.\index-workspace.ps1 -DryRun
# Lista os repositórios que seriam indexados sem executar
#>

param(
    [string]$Path = "$HOME\workspace",
    [int]$MaxDepth = 3,
    [switch]$Force,
    [string]$Include = "*",
    [string]$Exclude = "",
    [int]$Parallel = 1,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ============================================================
# Funções auxiliares
# ============================================================

function Find-CodebaseMemoryBinary {
    <#
    .SYNOPSIS
    Localiza o binário do codebase-memory-mcp no sistema.
    #>
    $cmd = Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $fallbackPath = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
    if (Test-Path $fallbackPath) {
        return $fallbackPath
    }

    return $null
}

function Find-GitRepositories {
    <#
    .SYNOPSIS
    Percorre o diretório raiz recursivamente até MaxDepth e retorna
    diretórios que contêm uma pasta .git (repositórios Git).

    .DESCRIPTION
    A busca é "greedy-stop": ao encontrar um .git em um diretório,
    aquele diretório é marcado como repositório e seus subdiretórios
    NÃO são percorridos (evita submodules e nested repos).
    #>
    param(
        [string]$RootPath,
        [int]$MaxDepth,
        [string]$IncludePattern,
        [string]$ExcludePattern
    )

    $repositories = [System.Collections.Generic.List[string]]::new()

    function Search-Recursive {
        param(
            [string]$CurrentPath,
            [int]$CurrentDepth
        )

        if ($CurrentDepth -gt $MaxDepth) {
            return
        }

        # Verificar se o diretório atual é um repositório Git
        $gitDir = Join-Path $CurrentPath ".git"
        if (Test-Path $gitDir) {
            $repoName = Split-Path $CurrentPath -Leaf

            # Aplicar filtros de include/exclude
            $included = $repoName -like $IncludePattern
            $excluded = ($ExcludePattern -ne "") -and ($repoName -like $ExcludePattern)

            if ($included -and -not $excluded) {
                $repositories.Add($CurrentPath)
            }

            # Não descer em subdiretórios (greedy-stop)
            return
        }

        # Não é um repo — continuar buscando nos subdiretórios
        try {
            $subdirs = Get-ChildItem -Path $CurrentPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^\.' -and $_.Name -ne 'node_modules' -and $_.Name -ne '__pycache__' }

            foreach ($subdir in $subdirs) {
                Search-Recursive -CurrentPath $subdir.FullName -CurrentDepth ($CurrentDepth + 1)
            }
        } catch {
            # Ignorar diretórios sem permissão de leitura
        }
    }

    Search-Recursive -CurrentPath $RootPath -CurrentDepth 0
    return $repositories
}

function Invoke-IndexRepository {
    <#
    .SYNOPSIS
    Indexa um único repositório com o codebase-memory-mcp.
    #>
    param(
        [string]$RepoPath,
        [string]$Binary,
        [switch]$ForceReindex
    )

    $repoName = Split-Path $RepoPath -Leaf
    $indexArgs = @("index")

    if ($ForceReindex) {
        $indexArgs += "--force"
    }

    $result = @{
        Name    = $repoName
        Path    = $RepoPath
        Status  = "pending"
        Message = ""
    }

    try {
        Push-Location $RepoPath
        $output = & $Binary @indexArgs 2>&1
        $result.Status = "success"
        $result.Message = "Indexado com sucesso"
    } catch {
        $result.Status = "error"
        $result.Message = $_.Exception.Message
    } finally {
        Pop-Location
    }

    return $result
}

# ============================================================
# Execução principal
# ============================================================

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Indexação Recursiva de Workspace (codebase-memory-mcp)    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# --- Validar binário ---
$cbmBin = Find-CodebaseMemoryBinary
if (-not $cbmBin) {
    Write-Host "ERRO: codebase-memory-mcp não encontrado." -ForegroundColor Red
    Write-Host "      Execute setup-codebase-memory.ps1 primeiro." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Binário: $cbmBin" -ForegroundColor Green

# --- Validar diretório raiz ---
if (!(Test-Path $Path)) {
    Write-Host "ERRO: Diretório raiz '$Path' não encontrado." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Workspace: $Path" -ForegroundColor Green
Write-Host "[..] Profundidade máxima: $MaxDepth" -ForegroundColor DarkGray

# --- Descobrir repositórios ---
Write-Host ""
Write-Host "Buscando repositórios Git..." -ForegroundColor Yellow

$repos = Find-GitRepositories -RootPath $Path -MaxDepth $MaxDepth -IncludePattern $Include -ExcludePattern $Exclude

if ($repos.Count -eq 0) {
    Write-Host ""
    Write-Host "Nenhum repositório Git encontrado em '$Path' (profundidade: $MaxDepth)." -ForegroundColor Yellow
    Write-Host "Verifique o caminho ou aumente -MaxDepth." -ForegroundColor DarkGray
    exit 0
}

Write-Host "Encontrados: $($repos.Count) repositório(s)" -ForegroundColor Green
Write-Host ""

# --- Listar repositórios ---
Write-Host "Repositórios identificados:" -ForegroundColor Cyan
Write-Host ("-" * 60) -ForegroundColor DarkGray
$index = 1
foreach ($repo in $repos) {
    $repoName = Split-Path $repo -Leaf
    $relativePath = $repo.Replace($Path, "").TrimStart("\", "/")
    Write-Host "  $index. $repoName" -ForegroundColor White -NoNewline
    Write-Host " ($relativePath)" -ForegroundColor DarkGray
    $index++
}
Write-Host ("-" * 60) -ForegroundColor DarkGray
Write-Host ""

# --- Modo DryRun ---
if ($DryRun) {
    Write-Host "[DRY-RUN] Nenhuma indexação executada. Use sem -DryRun para indexar." -ForegroundColor Yellow
    exit 0
}

# --- Executar indexação ---
$mode = if ($Force) { "Re-indexação completa (--force)" } else { "Incremental" }
Write-Host "Modo: $mode" -ForegroundColor Yellow
if ($Parallel -gt 1) {
    Write-Host "Paralelismo: $Parallel repositórios simultâneos" -ForegroundColor Yellow
}
Write-Host ""

$results = [System.Collections.Generic.List[hashtable]]::new()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

if ($Parallel -le 1) {
    # --- Execução sequencial ---
    $current = 0
    foreach ($repo in $repos) {
        $current++
        $repoName = Split-Path $repo -Leaf
        Write-Host "[$current/$($repos.Count)] Indexando: $repoName..." -ForegroundColor Cyan -NoNewline

        $result = Invoke-IndexRepository -RepoPath $repo -Binary $cbmBin -ForceReindex:$Force

        if ($result.Status -eq "success") {
            Write-Host " OK" -ForegroundColor Green
        } else {
            Write-Host " ERRO: $($result.Message)" -ForegroundColor Red
        }

        $results.Add($result)
    }
} else {
    # --- Execução paralela (PowerShell 7+) ---
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "AVISO: Execução paralela requer PowerShell 7+. Executando sequencialmente." -ForegroundColor Yellow
        $Parallel = 1

        $current = 0
        foreach ($repo in $repos) {
            $current++
            $repoName = Split-Path $repo -Leaf
            Write-Host "[$current/$($repos.Count)] Indexando: $repoName..." -ForegroundColor Cyan -NoNewline

            $result = Invoke-IndexRepository -RepoPath $repo -Binary $cbmBin -ForceReindex:$Force

            if ($result.Status -eq "success") {
                Write-Host " OK" -ForegroundColor Green
            } else {
                Write-Host " ERRO: $($result.Message)" -ForegroundColor Red
            }

            $results.Add($result)
        }
    } else {
        $repos | ForEach-Object -ThrottleLimit $Parallel -Parallel {
            $repo = $_
            $repoName = Split-Path $repo -Leaf
            $indexArgs = @("index")
            if ($using:Force) { $indexArgs += "--force" }

            try {
                Push-Location $repo
                & $using:cbmBin @indexArgs 2>&1 | Out-Null
                Write-Host "[OK] $repoName" -ForegroundColor Green
            } catch {
                Write-Host "[ERRO] $repoName : $($_.Exception.Message)" -ForegroundColor Red
            } finally {
                Pop-Location
            }
        }
    }
}

$stopwatch.Stop()

# --- Relatório final ---
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Relatório de Indexação                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$successCount = ($results | Where-Object { $_.Status -eq "success" }).Count
$errorCount = ($results | Where-Object { $_.Status -eq "error" }).Count

Write-Host "  Total de repositórios: $($repos.Count)" -ForegroundColor White
Write-Host "  Indexados com sucesso: $successCount" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "  Com erro:              $errorCount" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Repositórios com erro:" -ForegroundColor Red
    foreach ($r in ($results | Where-Object { $_.Status -eq "error" })) {
        Write-Host "    - $($r.Name): $($r.Message)" -ForegroundColor Red
    }
}
Write-Host "  Tempo total:           $($stopwatch.Elapsed.ToString('mm\:ss'))" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Dica: O codebase-memory-mcp mantém auto-sync via git." -ForegroundColor DarkGray
Write-Host "      Este script só é necessário para indexação inicial ou re-indexação forçada." -ForegroundColor DarkGray
Write-Host ""
