<#
.SYNOPSIS
Script para indexar (ou re-indexar) todo o código-fonte do diretório ~/workspace.

.DESCRIPTION
Este script invoca o mcp-vector-search para realizar a indexação completa do workspace.
Ele deve ser executado periodicamente ou após alterações significativas no código-fonte.
O script verifica se o Ollama está rodando e se o ambiente virtual está configurado.

.PARAMETER Path
Caminho do workspace a ser indexado. Padrão: $HOME\workspace.

.PARAMETER Extensions
Extensões de arquivo a serem indexadas. Padrão: .java,.kt,.py,.ts,.js,.go,.yaml,.yml,.xml,.json,.properties,.gradle,.proto,.graphql
#>

param(
    [string]$Path = "$HOME\workspace",
    [string]$Extensions = ".java,.kt,.py,.ts,.js,.go,.yaml,.yml,.xml,.json,.properties,.gradle,.proto,.graphql"
)

$ErrorActionPreference = "Stop"

$ToolsDir = "$HOME\local-tools"
$PythonVenvDir = "$ToolsDir\mcp-venv"
$MvsBin = "$PythonVenvDir\Scripts\mcp-vector-search.exe"

Write-Host "=== Indexação do Workspace ===" -ForegroundColor Cyan
Write-Host "Diretório alvo: $Path"
Write-Host "Extensões: $Extensions"

# Verificar pré-requisitos
if (!(Test-Path $MvsBin)) {
    Write-Host "ERRO: mcp-vector-search não encontrado. Execute setup.ps1 primeiro." -ForegroundColor Red
    exit 1
}

# Verificar se Ollama está rodando
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
    Write-Host "Ollama está rodando." -ForegroundColor Green
} catch {
    Write-Host "Ollama não está respondendo. Tentando iniciar..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

# Executar indexação
Write-Host "Iniciando indexação... Isso pode levar alguns minutos dependendo do tamanho do workspace." -ForegroundColor Yellow
& $MvsBin index --extensions $Extensions $Path

Write-Host "Indexação concluída com sucesso!" -ForegroundColor Green
Write-Host "O servidor MCP já pode responder consultas sobre o código indexado." -ForegroundColor Cyan
