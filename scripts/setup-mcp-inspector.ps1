<#
.SYNOPSIS
Script de instalação e execução do MCP Inspector para teste e debug de servidores MCP.

.DESCRIPTION
O MCP Inspector é a ferramenta visual oficial do Model Context Protocol para testar e
depurar servidores MCP. Ele fornece uma interface web (React) que permite interagir com
tools, resources e prompts expostos por qualquer servidor MCP.

Este script:
- Verifica se o Node.js está disponível no PATH
- Executa o MCP Inspector via npx (sem instalação global necessária)
- Permite apontar para qualquer servidor MCP local configurado no projeto

Requisitos:
- Node.js >= 18 (já instalado pelo setup-alternative-node.ps1 ou disponível no PATH)
- Nenhum privilégio de administrador necessário

.PARAMETER Server
Nome do servidor MCP a inspecionar. Valores aceitos: 'codebase-memory', 'serena', 'custom'.
Padrão: 'codebase-memory'.

.PARAMETER CustomCommand
Comando customizado para iniciar um servidor MCP não listado. Usado quando Server = 'custom'.

.PARAMETER Port
Porta do cliente web do Inspector. Padrão: 6274.

.EXAMPLE
.\setup-mcp-inspector.ps1
# Inspeciona o codebase-memory-mcp (padrão)

.EXAMPLE
.\setup-mcp-inspector.ps1 -Server serena
# Inspeciona o Serena MCP

.EXAMPLE
.\setup-mcp-inspector.ps1 -Server custom -CustomCommand "node C:\meu-server\index.js"
# Inspeciona um servidor MCP customizado
#>

param(
    [ValidateSet("codebase-memory", "serena", "custom")]
    [string]$Server = "codebase-memory",
    [string]$CustomCommand = "",
    [int]$Port = 6274
)

$ErrorActionPreference = "Stop"

$ToolsDir = "$HOME\local-tools"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  MCP Inspector - Teste Visual de Servidores MCP             ║" -ForegroundColor Cyan
Write-Host "║  https://github.com/modelcontextprotocol/inspector          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# 1. Verificar Node.js
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[1/3] Verificando Node.js..." -NoNewline

$nodePath = $null
$npxPath = $null

# Tentar Node.js do PATH global
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodePath = (Get-Command node).Source
    $npxPath = (Get-Command npx).Source
}

# Tentar Node.js local (instalado pelo setup-alternative-node.ps1)
if (-not $nodePath) {
    $localNodeDir = "$ToolsDir\node"
    if (Test-Path "$localNodeDir\node.exe") {
        $nodePath = "$localNodeDir\node.exe"
        $npxPath = "$localNodeDir\npx.cmd"
        $env:PATH = "$localNodeDir;$env:PATH"
    }
}

if (-not $nodePath) {
    Write-Host " FALHA" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Node.js nao encontrado. Execute primeiro:" -ForegroundColor Yellow
    Write-Host "    .\scripts\setup-alternative-node.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

$nodeVersion = & node --version 2>&1
Write-Host " OK ($nodeVersion em $nodePath)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 2. Resolver comando do servidor MCP
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[2/3] Resolvendo servidor MCP '$Server'..." -NoNewline

$inspectorArgs = @()

switch ($Server) {
    "codebase-memory" {
        # codebase-memory-mcp (binário estático no PATH ou em LOCALAPPDATA)
        $cbmBin = Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue
        if ($cbmBin) {
            $inspectorArgs = @($cbmBin.Source)
        } else {
            $cbmPath = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
            if (Test-Path $cbmPath) {
                $inspectorArgs = @($cbmPath)
            } else {
                Write-Host " FALHA" -ForegroundColor Red
                Write-Host ""
                Write-Host "  codebase-memory-mcp nao encontrado. Execute primeiro:" -ForegroundColor Yellow
                Write-Host "    .\scripts\setup-codebase-memory.ps1" -ForegroundColor White
                Write-Host ""
                exit 1
            }
        }
        Write-Host " OK (codebase-memory-mcp)" -ForegroundColor Green
    }
    "serena" {
        $serenaBin = Get-Command serena -ErrorAction SilentlyContinue
        if ($serenaBin) {
            $inspectorArgs = @($serenaBin.Source, "start-mcp-server", "--context=jb-copilot-plugin")
        } else {
            Write-Host " FALHA" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Serena nao encontrado. Execute primeiro:" -ForegroundColor Yellow
            Write-Host "    .\scripts\setup-serena.ps1" -ForegroundColor White
            Write-Host ""
            exit 1
        }
        Write-Host " OK (Serena MCP)" -ForegroundColor Green
    }
    "custom" {
        if ([string]::IsNullOrWhiteSpace($CustomCommand)) {
            Write-Host " FALHA" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Parametro -CustomCommand obrigatorio quando Server = 'custom'" -ForegroundColor Yellow
            Write-Host "  Exemplo: -CustomCommand 'node C:\meu-server\index.js'" -ForegroundColor White
            Write-Host ""
            exit 1
        }
        $parts = $CustomCommand -split " ", 2
        $inspectorArgs = @($parts[0])
        if ($parts.Length -gt 1) {
            $inspectorArgs += $parts[1] -split " "
        }
        Write-Host " OK (custom: $CustomCommand)" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. Executar MCP Inspector
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[3/3] Iniciando MCP Inspector..." -ForegroundColor White
Write-Host ""
Write-Host "  Interface web: http://localhost:$Port" -ForegroundColor Yellow
Write-Host "  Servidor alvo: $Server" -ForegroundColor Yellow
Write-Host "  Pressione Ctrl+C para encerrar" -ForegroundColor DarkGray
Write-Host ""

$env:CLIENT_PORT = $Port

# Executar o Inspector apontando para o servidor MCP escolhido
$npxArgs = @("-y", "@modelcontextprotocol/inspector") + $inspectorArgs

try {
    & npx $npxArgs
} catch {
    Write-Host ""
    Write-Host "  Erro ao executar MCP Inspector: $_" -ForegroundColor Red
    Write-Host "  Verifique se o Node.js >= 18 esta no PATH." -ForegroundColor Yellow
    exit 1
}
