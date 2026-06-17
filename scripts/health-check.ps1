<#
.SYNOPSIS
Verifica o estado de saúde de todos os componentes do RAG local.

.DESCRIPTION
Realiza verificações de conectividade e disponibilidade para:
- Ollama (API local)
- Modelo de embedding (nomic-embed-text)
- mcp-vector-search (binário e índice)
- Serena MCP (binário e inicialização)
- Configuração MCP do IntelliJ
#>

$ErrorActionPreference = "Continue"

Write-Host "=== Health Check: RAG Local + Serena ===" -ForegroundColor Cyan
Write-Host ""

$AllOk = $true

# 1. Verificar Python
Write-Host "[1/7] Python..." -NoNewline
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVersion = python --version 2>&1
    Write-Host " OK ($pyVersion)" -ForegroundColor Green
} else {
    Write-Host " FALHA (Python nao encontrado no PATH)" -ForegroundColor Red
    $AllOk = $false
}

# 2. Verificar Ollama
Write-Host "[2/7] Ollama..." -NoNewline
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
    $models = ($response.Content | ConvertFrom-Json).models
    Write-Host " OK (rodando, $($models.Count) modelo(s) disponivel(is))" -ForegroundColor Green
} catch {
    Write-Host " FALHA (Ollama nao esta respondendo em localhost:11434)" -ForegroundColor Red
    $AllOk = $false
}

# 3. Verificar modelo de embedding
Write-Host "[3/7] Modelo nomic-embed-text..." -NoNewline
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
    $models = ($response.Content | ConvertFrom-Json).models
    $hasEmbed = $models | Where-Object { $_.name -like "*nomic-embed*" }
    if ($hasEmbed) {
        Write-Host " OK (modelo encontrado)" -ForegroundColor Green
    } else {
        Write-Host " AVISO (modelo nao baixado, execute: ollama pull nomic-embed-text)" -ForegroundColor Yellow
        $AllOk = $false
    }
} catch {
    Write-Host " FALHA (nao foi possivel verificar)" -ForegroundColor Red
    $AllOk = $false
}

# 4. Verificar mcp-vector-search
Write-Host "[4/7] mcp-vector-search..." -NoNewline
$MvsBin = "$HOME\local-tools\mcp-venv\Scripts\mcp-vector-search.exe"
if (Test-Path $MvsBin) {
    Write-Host " OK (binario encontrado)" -ForegroundColor Green
} else {
    Write-Host " FALHA (nao instalado, execute setup.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 5. Verificar uv (package manager para Serena)
Write-Host "[5/7] uv (package manager)..." -NoNewline
if (Get-Command uv -ErrorAction SilentlyContinue) {
    $uvVersion = uv --version 2>&1
    Write-Host " OK ($uvVersion)" -ForegroundColor Green
} else {
    Write-Host " FALHA (uv nao encontrado, execute setup-serena.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 6. Verificar Serena MCP
Write-Host "[6/7] Serena MCP..." -NoNewline
if (Get-Command serena -ErrorAction SilentlyContinue) {
    $serenaVersion = serena --version 2>&1
    Write-Host " OK ($serenaVersion)" -ForegroundColor Green
} else {
    Write-Host " FALHA (serena nao encontrado, execute setup-serena.ps1)" -ForegroundColor Red
    $AllOk = $false
}

# 7. Verificar mcp.json do IntelliJ
Write-Host "[7/7] Configuracao MCP IntelliJ..." -NoNewline
$McpJsonPath = "$HOME\.config\github-copilot\intellij\mcp.json"
if (Test-Path $McpJsonPath) {
    $content = Get-Content $McpJsonPath -Raw | ConvertFrom-Json
    $hasRag = $content.servers."mcp-vector-search" -or $content.mcpServers."local-code-rag"
    $hasSerena = $content.servers."serena"

    if ($hasRag -and $hasSerena) {
        Write-Host " OK (RAG + Serena configurados)" -ForegroundColor Green
    } elseif ($hasRag) {
        Write-Host " PARCIAL (RAG OK, Serena nao configurado)" -ForegroundColor Yellow
        $AllOk = $false
    } elseif ($hasSerena) {
        Write-Host " PARCIAL (Serena OK, RAG nao configurado)" -ForegroundColor Yellow
        $AllOk = $false
    } else {
        Write-Host " AVISO (mcp.json existe mas servidores nao configurados)" -ForegroundColor Yellow
        $AllOk = $false
    }
} else {
    Write-Host " FALHA (mcp.json nao encontrado, execute setup.ps1 e setup-serena.ps1)" -ForegroundColor Red
    $AllOk = $false
}

Write-Host ""
if ($AllOk) {
    Write-Host "Todos os componentes estao operacionais." -ForegroundColor Green
    Write-Host ""
    Write-Host "Componentes ativos:" -ForegroundColor White
    Write-Host "  [RAG Vetorial] mcp-vector-search + Ollama + LanceDB" -ForegroundColor Gray
    Write-Host "  [Navegacao LSP] Serena MCP (find_symbol, references, implementations)" -ForegroundColor Gray
} else {
    Write-Host "Alguns componentes precisam de atencao. Verifique os itens acima." -ForegroundColor Yellow
}
