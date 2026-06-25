<#
.SYNOPSIS
Script para indexar (ou re-indexar) todo o código-fonte do diretório ~/workspace.

.DESCRIPTION
Este script invoca o codebase-memory-mcp para realizar a indexação completa do workspace.
Ele deve ser executado periodicamente ou após alterações significativas no código-fonte.
O codebase-memory-mcp mantém auto-sync via git-based change detection, mas este script
permite forçar uma re-indexação completa quando necessário.

.PARAMETER Path
Caminho do workspace a ser indexado. Padrão: $HOME\workspace.

.PARAMETER Force
Força re-indexação completa (ignora cache incremental).

.EXAMPLE
.\index-workspace.ps1
# Indexa o workspace padrão (~\workspace)

.EXAMPLE
.\index-workspace.ps1 -Path "C:\projetos\meu-servico"
# Indexa um diretório específico

.EXAMPLE
.\index-workspace.ps1 -Force
# Força re-indexação completa ignorando cache
#>

param(
    [string]$Path = "$HOME\workspace",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== Indexação do Workspace (codebase-memory-mcp) ===" -ForegroundColor Cyan
Write-Host "Diretório alvo: $Path"

# Verificar codebase-memory-mcp
$cbmBin = Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue
if (-not $cbmBin) {
    $cbmPath = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
    if (Test-Path $cbmPath) {
        $cbmBin = $cbmPath
    } else {
        Write-Host "ERRO: codebase-memory-mcp nao encontrado. Execute setup-codebase-memory.ps1 primeiro." -ForegroundColor Red
        exit 1
    }
} else {
    $cbmBin = $cbmBin.Source
}

# Verificar se o diretório existe
if (!(Test-Path $Path)) {
    Write-Host "ERRO: Diretório '$Path' nao encontrado." -ForegroundColor Red
    exit 1
}

# Executar indexação
Write-Host ""
Write-Host "Iniciando indexação... Isso pode levar alguns minutos dependendo do tamanho do workspace." -ForegroundColor Yellow

$indexArgs = @("index")
if ($Force) {
    $indexArgs += "--force"
    Write-Host "Modo: Re-indexação completa (--force)" -ForegroundColor Yellow
} else {
    Write-Host "Modo: Incremental (apenas alterações desde último index)" -ForegroundColor Green
}

Push-Location $Path
try {
    & $cbmBin @indexArgs
    Write-Host ""
    Write-Host "Indexação concluída com sucesso!" -ForegroundColor Green
    Write-Host "O servidor MCP já pode responder consultas sobre o código indexado." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Dica: O codebase-memory-mcp mantém auto-sync via git." -ForegroundColor DarkGray
    Write-Host "      Este script só é necessário para a indexação inicial ou re-indexação forçada." -ForegroundColor DarkGray
} finally {
    Pop-Location
}
