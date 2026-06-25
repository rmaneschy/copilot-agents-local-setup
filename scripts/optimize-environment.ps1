<#
.SYNOPSIS
    Aplica otimizações de desempenho ao ambiente de code intelligence local.

.DESCRIPTION
    Este script configura Ollama keep-alive (opcional, para LLM local),
    verifica o estado do knowledge graph e aquece os componentes para uso imediato.

    Nota: O codebase-memory-mcp é auto-otimizado (SQLite WAL mode, auto-vacuum).
    Este script foca em otimizações do Ollama (LLM local) e verificação geral.

.PARAMETER WarmUp
    Configura Ollama keep-alive e aquece o modelo de LLM (opcional).

.PARAMETER VerifyGraph
    Verifica o estado do knowledge graph do codebase-memory-mcp.

.PARAMETER All
    Executa todas as otimizações e verificações.

.EXAMPLE
    .\optimize-environment.ps1 -All
    .\optimize-environment.ps1 -WarmUp
    .\optimize-environment.ps1 -VerifyGraph
#>

param(
    [switch]$WarmUp,
    [switch]$VerifyGraph,
    [switch]$All
)

$ErrorActionPreference = "Stop"

if (-not ($WarmUp -or $VerifyGraph -or $All)) {
    Write-Host "Uso: .\optimize-environment.ps1 -All" -ForegroundColor Yellow
    Write-Host "     .\optimize-environment.ps1 -WarmUp"
    Write-Host "     .\optimize-environment.ps1 -VerifyGraph"
    Write-Host ""
    Write-Host "Flags disponíveis:" -ForegroundColor Cyan
    Write-Host "  -WarmUp       Configura keep-alive e aquece Ollama (LLM local)"
    Write-Host "  -VerifyGraph  Verifica estado do knowledge graph (codebase-memory-mcp)"
    Write-Host "  -All          Executa todas as otimizações e verificações"
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Otimização de Ambiente: Code Intelligence Local" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────
# ETAPA 1: Ollama Keep-Alive e Warm-Up (Opcional)
# ─────────────────────────────────────────────
if ($All -or $WarmUp) {
    Write-Host "[1/3] Configurando Ollama keep-alive (LLM local)..." -ForegroundColor Cyan

    $currentKeepAlive = [System.Environment]::GetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "User")
    if ($currentKeepAlive -ne "-1") {
        [System.Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "-1", "User")
        Write-Host "  Variável OLLAMA_KEEP_ALIVE definida como '-1' (permanente)" -ForegroundColor Green
    } else {
        Write-Host "  OLLAMA_KEEP_ALIVE já configurado" -ForegroundColor Gray
    }

    # Verificar se Ollama está rodando
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 3 -ErrorAction Stop
        $models = ($response.Content | ConvertFrom-Json).models
        Write-Host "  Ollama ativo com $($models.Count) modelo(s)" -ForegroundColor Green
    } catch {
        Write-Host "  AVISO - Ollama não está rodando (opcional, apenas para LLM local)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ─────────────────────────────────────────────
# ETAPA 2: Verificar Knowledge Graph
# ─────────────────────────────────────────────
if ($All -or $VerifyGraph) {
    Write-Host "[2/3] Verificando knowledge graph (codebase-memory-mcp)..." -ForegroundColor Cyan

    $cbmBin = Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue
    if (-not $cbmBin) {
        $cbmPath = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
        if (Test-Path $cbmPath) {
            $cbmBin = $cbmPath
        }
    } else {
        $cbmBin = $cbmBin.Source
    }

    if ($cbmBin) {
        $version = & $cbmBin --version 2>&1
        Write-Host "  Versão: $version" -ForegroundColor Green

        # Verificar se há índice no diretório atual
        $graphPath = ".codebase-memory"
        if (Test-Path $graphPath) {
            $graphSize = (Get-ChildItem $graphPath -Recurse | Measure-Object -Property Length -Sum).Sum
            $graphSizeMB = [math]::Round($graphSize / 1MB, 2)
            Write-Host "  Knowledge graph: $graphSizeMB MB" -ForegroundColor Green
        } else {
            Write-Host "  Knowledge graph: Nao indexado neste diretório" -ForegroundColor Yellow
            Write-Host "  Execute: codebase-memory-mcp index" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  FALHA - codebase-memory-mcp nao encontrado" -ForegroundColor Red
        Write-Host "  Execute: .\scripts\setup-codebase-memory.ps1" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ─────────────────────────────────────────────
# ETAPA 3: Resumo Final
# ─────────────────────────────────────────────
Write-Host "[3/3] Estado do ambiente..." -ForegroundColor Cyan
Write-Host ""

$keepAlive = [System.Environment]::GetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "User")
$ollamaStatus = if ($keepAlive -eq "-1") { "Permanente (-1)" } else { "Padrão (5min)" }

Write-Host "  ┌─────────────────────────────────────────────────────────────┐"
Write-Host "  │ Code Intelligence:  codebase-memory-mcp (knowledge graph)"
Write-Host "  │ Navegação LSP:      Serena MCP"
Write-Host "  │ Ollama keep-alive:  $ollamaStatus (opcional, LLM local)"
Write-Host "  └─────────────────────────────────────────────────────────────┘"
Write-Host ""
Write-Host "Otimização concluída!" -ForegroundColor Green
Write-Host ""
Write-Host "Nota: O codebase-memory-mcp é auto-otimizado (SQLite WAL, auto-vacuum)." -ForegroundColor DarkGray
Write-Host "      Não requer otimização manual de índices ou compactação." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Yellow
Write-Host "  1. Verifique saúde: .\scripts\health-check.ps1"
Write-Host "  2. Indexe o workspace: .\scripts\index-workspace.ps1"
Write-Host "  3. Abra os projetos no IntelliJ e use o Copilot Agent Mode"
Write-Host ""
