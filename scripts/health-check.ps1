<#
.SYNOPSIS
Verifica o estado de saúde de todos os componentes do code intelligence local.

.DESCRIPTION
Realiza verificações de conectividade e disponibilidade para:
- codebase-memory-mcp (binário e versão)
- Serena MCP (binário e inicialização)
- Configuração MCP do IntelliJ
- Ollama (opcional, API local)
#>

$ErrorActionPreference = "Continue"

Write-Host "=== Health Check: Code Intelligence Local ===" -ForegroundColor Cyan
Write-Host ""

$AllOk = $true

# 1. Verificar codebase-memory-mcp
Write-Host "[1/5] codebase-memory-mcp..." -NoNewline
if (Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue) {
    $cbmVersion = codebase-memory-mcp --version 2>&1
    Write-Host " OK ($cbmVersion)" -ForegroundColor Green
} else {
    $cbmBin = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
    if (Test-Path $cbmBin) {
        $cbmVersion = & $cbmBin --version 2>&1
        Write-Host " OK ($cbmVersion, nao esta no PATH)" -ForegroundColor Yellow
    } else {
        Write-Host " FALHA (nao instalado, execute setup-codebase-memory.ps1)" -ForegroundColor Red
        $AllOk = $false
    }
}

# 2. Verificar uv (package manager para Serena)
Write-Host "[2/5] uv (package manager)..." -NoNewline
if (Get-Command uv -ErrorAction SilentlyContinue) {
    $uvVersion = uv --version 2>&1
    Write-Host " OK ($uvVersion)" -ForegroundColor Green
} else {
    Write-Host " FALHA (uv nao encontrado, execute setup-serena.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 3. Verificar Serena MCP
Write-Host "[3/5] Serena MCP..." -NoNewline
if (Get-Command serena -ErrorAction SilentlyContinue) {
    $serenaVersion = serena --version 2>&1
    Write-Host " OK ($serenaVersion)" -ForegroundColor Green
} else {
    Write-Host " FALHA (serena nao encontrado, execute setup-serena.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 4. Verificar mcp.json do IntelliJ
Write-Host "[4/5] Configuracao MCP IntelliJ..." -NoNewline
$McpJsonPath = "$HOME\.config\github-copilot\intellij\mcp.json"
if (Test-Path $McpJsonPath) {
    $content = Get-Content $McpJsonPath -Raw | ConvertFrom-Json
    $hasCbm = $content.servers."codebase-memory" -or $content.mcpServers."codebase-memory"
    $hasSerena = $content.servers."serena" -or $content.mcpServers."serena"

    if ($hasCbm -and $hasSerena) {
        Write-Host " OK (codebase-memory + Serena configurados)" -ForegroundColor Green
    } elseif ($hasCbm) {
        Write-Host " PARCIAL (codebase-memory OK, Serena nao configurado)" -ForegroundColor Yellow
        $AllOk = $false
    } elseif ($hasSerena) {
        Write-Host " PARCIAL (Serena OK, codebase-memory nao configurado)" -ForegroundColor Yellow
        $AllOk = $false
    } else {
        Write-Host " AVISO (mcp.json existe mas servidores nao configurados)" -ForegroundColor Yellow
        $AllOk = $false
    }
} else {
    Write-Host " FALHA (mcp.json nao encontrado, execute setup-codebase-memory.ps1 e setup-serena.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 5. Verificar Ollama (opcional)
Write-Host "[5/5] Ollama (opcional)..." -NoNewline
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 3 -ErrorAction Stop
    $models = ($response.Content | ConvertFrom-Json).models
    Write-Host " OK (rodando, $($models.Count) modelo(s))" -ForegroundColor Green
} catch {
    Write-Host " NAO ATIVO (opcional, apenas para LLM local)" -ForegroundColor DarkGray
}

Write-Host ""
if ($AllOk) {
    Write-Host "Todos os componentes essenciais estao operacionais." -ForegroundColor Green
    Write-Host ""
    Write-Host "Componentes ativos:" -ForegroundColor White
    Write-Host "  [Code Intelligence] codebase-memory-mcp (knowledge graph + busca semantica)" -ForegroundColor Gray
    Write-Host "  [Navegacao LSP]     Serena MCP (find_symbol, references, implementations)" -ForegroundColor Gray
} else {
    Write-Host "Alguns componentes precisam de atencao. Verifique os itens acima." -ForegroundColor Yellow
}
