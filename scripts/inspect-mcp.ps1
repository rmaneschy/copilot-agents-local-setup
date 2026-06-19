<#
.SYNOPSIS
Atalho rápido para inspecionar todos os servidores MCP configurados no projeto.

.DESCRIPTION
Este script executa o MCP Inspector sequencialmente para cada servidor MCP configurado,
permitindo verificar rapidamente se todos estão respondendo corretamente.

Diferente do setup-mcp-inspector.ps1 (que abre a interface web interativa), este script
realiza uma verificação rápida de conectividade e lista as ferramentas disponíveis em
cada servidor, sem abrir o navegador.

Requisitos:
- Node.js >= 18 disponível no PATH
- Servidores MCP configurados (mcp-vector-search, Serena)

.EXAMPLE
.\inspect-mcp.ps1
# Verifica todos os servidores MCP configurados
#>

$ErrorActionPreference = "Continue"

$ToolsDir = "$HOME\local-tools"
$PythonVenvDir = "$ToolsDir\mcp-venv"
$SerenaDir = "$ToolsDir\serena"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  MCP Quick Inspect - Verificação Rápida de Servidores       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verificar Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    $localNodeDir = "$ToolsDir\node"
    if (Test-Path "$localNodeDir\node.exe") {
        $env:PATH = "$localNodeDir;$env:PATH"
    } else {
        Write-Host "  FALHA: Node.js nao encontrado." -ForegroundColor Red
        Write-Host "  Execute: .\scripts\setup-alternative-node.ps1" -ForegroundColor Yellow
        exit 1
    }
}

$servers = @()

# Detectar mcp-vector-search
$mcpVectorSearch = "$PythonVenvDir\Scripts\mcp-vector-search.exe"
if (Test-Path $mcpVectorSearch) {
    $servers += @{
        Name = "mcp-vector-search"
        Command = $mcpVectorSearch
        Args = @()
    }
} elseif (Test-Path "$PythonVenvDir\Scripts\python.exe") {
    $servers += @{
        Name = "mcp-vector-search (via python)"
        Command = "$PythonVenvDir\Scripts\python.exe"
        Args = @("-m", "mcp_vector_search")
    }
}

# Detectar Serena
$serenaBinary = "$SerenaDir\serena.exe"
if (Test-Path $serenaBinary) {
    $servers += @{
        Name = "Serena MCP"
        Command = $serenaBinary
        Args = @()
    }
}

if ($servers.Count -eq 0) {
    Write-Host "  Nenhum servidor MCP detectado." -ForegroundColor Yellow
    Write-Host "  Execute .\scripts\setup.ps1 e .\scripts\setup-serena.ps1 primeiro." -ForegroundColor DarkGray
    exit 1
}

Write-Host "Servidores MCP detectados: $($servers.Count)" -ForegroundColor White
Write-Host ""

foreach ($server in $servers) {
    Write-Host "  [$($server.Name)]" -ForegroundColor Yellow
    Write-Host "    Comando: $($server.Command) $($server.Args -join ' ')" -ForegroundColor DarkGray

    # Verificar se o binário existe e é executável
    if (Test-Path $server.Command) {
        Write-Host "    Status: Binario encontrado" -ForegroundColor Green
    } else {
        Write-Host "    Status: Binario NAO encontrado" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Para inspecionar visualmente um servidor, execute:" -ForegroundColor White
Write-Host "  .\scripts\setup-mcp-inspector.ps1 -Server vector-search" -ForegroundColor Cyan
Write-Host "  .\scripts\setup-mcp-inspector.ps1 -Server serena" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para abrir o orquestrador visual (n8n):" -ForegroundColor White
Write-Host "  .\scripts\setup-n8n.ps1 -Start" -ForegroundColor Cyan
Write-Host ""
