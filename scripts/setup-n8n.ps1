<#
.SYNOPSIS
Script de instalação e configuração do n8n como orquestrador visual de agentes.

.DESCRIPTION
O n8n é uma plataforma de automação de workflows com suporte nativo a agentes de IA
e ao Model Context Protocol (MCP). Ele fornece um canvas visual onde o desenvolvedor
pode desenhar fluxos multi-agentes conectando LLMs locais (Ollama), servidores MCP
(codebase-memory-mcp, Serena) e integrações externas (Jira, GitHub, etc.).

Este script:
- Verifica se o Node.js está disponível no PATH
- Instala o n8n localmente (sem privilégio de administrador)
- Configura variáveis de ambiente para uso local
- Cria um atalho para iniciar o n8n

Requisitos:
- Node.js >= 18 (já instalado pelo setup-alternative-node.ps1 ou disponível no PATH)
- Nenhum privilégio de administrador necessário
- ~200MB de espaço em disco

.PARAMETER Uninstall
Remove o n8n e seus dados locais.

.PARAMETER Start
Apenas inicia o n8n (sem reinstalar). Útil para uso diário.

.PARAMETER Port
Porta HTTP do n8n. Padrão: 5678.

.EXAMPLE
.\setup-n8n.ps1
# Instala o n8n localmente

.EXAMPLE
.\setup-n8n.ps1 -Start
# Inicia o n8n (após instalação)

.EXAMPLE
.\setup-n8n.ps1 -Uninstall
# Remove o n8n e dados locais
#>

param(
    [switch]$Uninstall,
    [switch]$Start,
    [int]$Port = 5678
)

$ErrorActionPreference = "Stop"

$ToolsDir = "$HOME\local-tools"
$N8nDir = "$ToolsDir\n8n"
$N8nDataDir = "$N8nDir\data"
$N8nNodeModules = "$N8nDir\node_modules"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  n8n - Orquestrador Visual de Agentes                       ║" -ForegroundColor Cyan
Write-Host "║  https://n8n.io                                             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# Desinstalação
# ═══════════════════════════════════════════════════════════════════════════
if ($Uninstall) {
    Write-Host "Removendo n8n..." -ForegroundColor Yellow
    if (Test-Path $N8nDir) {
        Remove-Item -Recurse -Force $N8nDir
        Write-Host "  OK: Diretorio $N8nDir removido" -ForegroundColor Green
    } else {
        Write-Host "  n8n nao encontrado em $N8nDir" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Desinstalacao concluida." -ForegroundColor Green
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 1. Verificar Node.js
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[1/4] Verificando Node.js..." -NoNewline

$nodePath = $null

# Tentar Node.js do PATH global
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodePath = (Get-Command node).Source
}

# Tentar Node.js local (instalado pelo setup-alternative-node.ps1)
if (-not $nodePath) {
    $localNodeDir = "$ToolsDir\node"
    if (Test-Path "$localNodeDir\node.exe") {
        $nodePath = "$localNodeDir\node.exe"
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
Write-Host " OK ($nodeVersion)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 2. Criar diretórios
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[2/4] Preparando diretorios..." -NoNewline

@($N8nDir, $N8nDataDir) | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null }
}
Write-Host " OK ($N8nDir)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 3. Instalar n8n (local, sem -g)
# ═══════════════════════════════════════════════════════════════════════════
if (-not $Start) {
    Write-Host "[3/4] Instalando n8n (local)..." -ForegroundColor White

    # Inicializar package.json se não existir
    if (-not (Test-Path "$N8nDir\package.json")) {
        Push-Location $N8nDir
        & npm init -y 2>&1 | Out-Null
        Pop-Location
    }

    # Instalar n8n como dependência local
    Push-Location $N8nDir
    Write-Host "  Baixando pacotes (pode levar alguns minutos)..." -ForegroundColor DarkGray
    & npm install n8n 2>&1 | ForEach-Object {
        if ($_ -match "added \d+ packages") {
            Write-Host "  $_" -ForegroundColor Green
        }
    }
    Pop-Location

    if (-not (Test-Path "$N8nNodeModules\.bin\n8n.cmd")) {
        Write-Host "  FALHA: n8n nao foi instalado corretamente" -ForegroundColor Red
        exit 1
    }

    Write-Host "  OK: n8n instalado em $N8nDir" -ForegroundColor Green
} else {
    Write-Host "[3/4] Pulando instalacao (modo -Start)..." -ForegroundColor DarkGray

    if (-not (Test-Path "$N8nNodeModules\.bin\n8n.cmd")) {
        Write-Host "  FALHA: n8n nao encontrado. Execute sem -Start primeiro." -ForegroundColor Red
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. Iniciar n8n
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[4/4] Iniciando n8n..." -ForegroundColor White
Write-Host ""

# Configurar variáveis de ambiente para o n8n
$env:N8N_PORT = $Port
$env:N8N_USER_FOLDER = $N8nDataDir
$env:N8N_DIAGNOSTICS_ENABLED = "false"
$env:N8N_PERSONALIZATION_ENABLED = "false"
$env:N8N_TEMPLATES_ENABLED = "true"

# Configurar para uso com Ollama local
$env:N8N_AI_ENABLED = "true"

Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "  │  n8n esta iniciando...                                  │" -ForegroundColor Green
Write-Host "  │                                                         │" -ForegroundColor Green
Write-Host "  │  Interface web: http://localhost:$Port                   │" -ForegroundColor Green
Write-Host "  │  Dados locais:  $N8nDataDir              │" -ForegroundColor Green
Write-Host "  │                                                         │" -ForegroundColor Green
Write-Host "  │  Dica: Use o no 'MCP Client Tool' para conectar os     │" -ForegroundColor Green
Write-Host "  │  servidores MCP locais (codebase-memory-mcp, Serena).         │" -ForegroundColor Green
Write-Host "  │                                                         │" -ForegroundColor Green
Write-Host "  │  Pressione Ctrl+C para encerrar                        │" -ForegroundColor Green
Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""

# Executar n8n
$n8nBin = "$N8nNodeModules\.bin\n8n.cmd"
try {
    & $n8nBin start
} catch {
    Write-Host ""
    Write-Host "  Erro ao iniciar n8n: $_" -ForegroundColor Red
    Write-Host "  Verifique se a porta $Port nao esta em uso." -ForegroundColor Yellow
    exit 1
}
