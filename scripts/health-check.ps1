<#
.SYNOPSIS
Verifica o estado de saúde de todos os componentes do RAG local.

.DESCRIPTION
Realiza verificações de conectividade e disponibilidade para:
- Ollama (API local)
- Modelo de embedding (nomic-embed-text)
- mcp-vector-search (binário e índice)
- Configuração MCP do IntelliJ
#>

$ErrorActionPreference = "Continue"

Write-Host "=== Health Check: RAG Local ===" -ForegroundColor Cyan
Write-Host ""

$AllOk = $true

# 1. Verificar Python
Write-Host "[1/5] Python..." -NoNewline
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVersion = python --version 2>&1
    Write-Host " OK ($pyVersion)" -ForegroundColor Green
} else {
    Write-Host " FALHA (Python não encontrado no PATH)" -ForegroundColor Red
    $AllOk = $false
}

# 2. Verificar Ollama
Write-Host "[2/5] Ollama..." -NoNewline
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
    $models = ($response.Content | ConvertFrom-Json).models
    Write-Host " OK (rodando, $($models.Count) modelo(s) disponível(is))" -ForegroundColor Green
} catch {
    Write-Host " FALHA (Ollama não está respondendo em localhost:11434)" -ForegroundColor Red
    $AllOk = $false
}

# 3. Verificar modelo de embedding
Write-Host "[3/5] Modelo nomic-embed-text..." -NoNewline
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
    $models = ($response.Content | ConvertFrom-Json).models
    $hasEmbed = $models | Where-Object { $_.name -like "*nomic-embed*" }
    if ($hasEmbed) {
        Write-Host " OK (modelo encontrado)" -ForegroundColor Green
    } else {
        Write-Host " AVISO (modelo não baixado, execute: ollama pull nomic-embed-text)" -ForegroundColor Yellow
        $AllOk = $false
    }
} catch {
    Write-Host " FALHA (não foi possível verificar)" -ForegroundColor Red
    $AllOk = $false
}

# 4. Verificar mcp-vector-search
Write-Host "[4/5] mcp-vector-search..." -NoNewline
$MvsBin = "$HOME\local-tools\mcp-venv\Scripts\mcp-vector-search.exe"
if (Test-Path $MvsBin) {
    Write-Host " OK (binário encontrado)" -ForegroundColor Green
} else {
    Write-Host " FALHA (não instalado, execute setup.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 5. Verificar mcp.json do IntelliJ
Write-Host "[5/5] Configuração MCP IntelliJ..." -NoNewline
$McpJsonPath = "$HOME\.config\github-copilot\intellij\mcp.json"
if (Test-Path $McpJsonPath) {
    $content = Get-Content $McpJsonPath -Raw | ConvertFrom-Json
    if ($content.mcpServers."local-code-rag") {
        Write-Host " OK (servidor 'local-code-rag' configurado)" -ForegroundColor Green
    } else {
        Write-Host " AVISO (mcp.json existe mas servidor não configurado)" -ForegroundColor Yellow
        $AllOk = $false
    }
} else {
    Write-Host " FALHA (mcp.json não encontrado, execute setup.ps1)" -ForegroundColor Red
    $AllOk = $false
}

Write-Host ""
if ($AllOk) {
    Write-Host "Todos os componentes estão operacionais." -ForegroundColor Green
} else {
    Write-Host "Alguns componentes precisam de atenção. Verifique os itens acima." -ForegroundColor Yellow
}
