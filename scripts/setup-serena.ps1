<#
.SYNOPSIS
    Instala e configura o Serena MCP para integração com GitHub Copilot no IntelliJ.

.DESCRIPTION
    Este script automatiza a instalação do Serena MCP, que fornece ferramentas
    semânticas de navegação de código (via LSP) ao GitHub Copilot Agent Mode.
    O Serena complementa o RAG vetorial com capacidades determinísticas de
    find-symbol, find-references, rename e refactoring.

    Pré-requisitos:
    - Windows 11 (sem necessidade de admin)
    - Acesso à internet para download do uv e do Serena

.NOTES
    Autor: Rodrigo Maneschy
    Versão: 1.0.0
#>

param(
    [string]$WorkspacePath = "$env:USERPROFILE\workspace"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Serena MCP - Setup para GitHub Copilot   " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------
# Etapa 1: Verificar/Instalar uv (package manager)
# -----------------------------------------------
Write-Host "[1/5] Verificando instalacao do uv..." -ForegroundColor Yellow

$uvPath = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvPath) {
    Write-Host "  uv nao encontrado. Instalando..." -ForegroundColor Gray
    try {
        powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        # Atualizar PATH para a sessao atual
        $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
        Write-Host "  uv instalado com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERRO: Falha ao instalar uv. Instale manualmente: https://docs.astral.sh/uv/getting-started/installation/" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "  uv encontrado: $($uvPath.Source)" -ForegroundColor Green
}

# -----------------------------------------------
# Etapa 2: Instalar Serena via uv
# -----------------------------------------------
Write-Host ""
Write-Host "[2/5] Instalando Serena MCP..." -ForegroundColor Yellow

try {
    uv tool install -p 3.13 serena-agent
    Write-Host "  Serena instalado com sucesso!" -ForegroundColor Green
}
catch {
    Write-Host "  Tentando atualizar instalacao existente..." -ForegroundColor Gray
    try {
        uv tool upgrade serena-agent
        Write-Host "  Serena atualizado com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERRO: Falha ao instalar/atualizar Serena." -ForegroundColor Red
        exit 1
    }
}

# -----------------------------------------------
# Etapa 3: Inicializar Serena (language servers)
# -----------------------------------------------
Write-Host ""
Write-Host "[3/5] Inicializando Serena (backend: language servers)..." -ForegroundColor Yellow

try {
    serena init
    Write-Host "  Serena inicializado com sucesso!" -ForegroundColor Green
}
catch {
    Write-Host "  AVISO: Inicializacao pode requerer interacao manual." -ForegroundColor DarkYellow
    Write-Host "  Execute 'serena init' manualmente se necessario." -ForegroundColor DarkYellow
}

# -----------------------------------------------
# Etapa 4: Configurar MCP no IntelliJ (GitHub Copilot)
# -----------------------------------------------
Write-Host ""
Write-Host "[4/5] Configurando MCP para GitHub Copilot no IntelliJ..." -ForegroundColor Yellow

$mcpConfigDir = "$env:USERPROFILE\.config\github-copilot\intellij"
$mcpConfigFile = Join-Path $mcpConfigDir "mcp.json"

# Verificar se o arquivo mcp.json ja existe
if (Test-Path $mcpConfigFile) {
    Write-Host "  Arquivo mcp.json existente encontrado. Adicionando Serena..." -ForegroundColor Gray
    try {
        $existingConfig = Get-Content $mcpConfigFile -Raw | ConvertFrom-Json

        # Verificar se servers existe
        if (-not $existingConfig.servers) {
            $existingConfig | Add-Member -NotePropertyName "servers" -NotePropertyValue @{}
        }

        # Adicionar entrada do Serena
        $serenaConfig = @{
            type    = "stdio"
            command = "serena"
            args    = @("start-mcp-server", "--context=jb-copilot-plugin")
        }

        # Converter para objeto adequado
        $existingConfig.servers | Add-Member -NotePropertyName "serena" -NotePropertyValue $serenaConfig -Force

        $existingConfig | ConvertTo-Json -Depth 10 | Set-Content $mcpConfigFile -Encoding UTF8
        Write-Host "  Serena adicionado ao mcp.json existente!" -ForegroundColor Green
    }
    catch {
        Write-Host "  AVISO: Nao foi possivel modificar mcp.json automaticamente." -ForegroundColor DarkYellow
        Write-Host "  Adicione manualmente a entrada do Serena (veja README)." -ForegroundColor DarkYellow
    }
}
else {
    # Criar diretorio se nao existir
    if (-not (Test-Path $mcpConfigDir)) {
        New-Item -ItemType Directory -Path $mcpConfigDir -Force | Out-Null
    }

    # Criar mcp.json com ambos os servidores (RAG + Serena)
    $mcpConfig = @{
        servers = @{
            serena             = @{
                type    = "stdio"
                command = "serena"
                args    = @("start-mcp-server", "--context=jb-copilot-plugin")
            }
            "mcp-vector-search" = @{
                type    = "stdio"
                command = "python"
                args    = @("-m", "mcp_vector_search", "--db-path", "$env:USERPROFILE\.local\share\mcp-vector-search\lancedb")
            }
        }
    }

    $mcpConfig | ConvertTo-Json -Depth 10 | Set-Content $mcpConfigFile -Encoding UTF8
    Write-Host "  mcp.json criado com Serena + mcp-vector-search!" -ForegroundColor Green
}

# -----------------------------------------------
# Etapa 5: Verificacao final
# -----------------------------------------------
Write-Host ""
Write-Host "[5/5] Verificacao final..." -ForegroundColor Yellow

$serenaCmd = Get-Command serena -ErrorAction SilentlyContinue
if ($serenaCmd) {
    Write-Host "  Serena disponivel no PATH: $($serenaCmd.Source)" -ForegroundColor Green
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  INSTALACAO CONCLUIDA COM SUCESSO!        " -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Proximos passos:" -ForegroundColor White
    Write-Host "  1. Reinicie o IntelliJ IDEA" -ForegroundColor Gray
    Write-Host "  2. Abra o Copilot Chat em Agent Mode" -ForegroundColor Gray
    Write-Host "  3. Clique em 'Tools' e verifique se Serena aparece" -ForegroundColor Gray
    Write-Host "  4. No chat, digite:" -ForegroundColor Gray
    Write-Host '     "Ative o projeto atual com Serena"' -ForegroundColor White
    Write-Host ""
    Write-Host "Dica: Desabilite as tools built-in redundantes:" -ForegroundColor DarkYellow
    Write-Host "  - replace_string_in_file" -ForegroundColor Gray
    Write-Host "  - apply_patch" -ForegroundColor Gray
    Write-Host "  - list_dir" -ForegroundColor Gray
    Write-Host "  - file_search" -ForegroundColor Gray
    Write-Host "  - grep_search" -ForegroundColor Gray
}
else {
    Write-Host "  AVISO: Comando 'serena' nao encontrado no PATH." -ForegroundColor Red
    Write-Host "  Reinicie o terminal e tente novamente." -ForegroundColor Red
}
