<#
.SYNOPSIS
    Instala e configura o codebase-memory-mcp para code intelligence via knowledge graph.

.DESCRIPTION
    Este script automatiza a instalação do codebase-memory-mcp, um motor de code intelligence
    de alta performance que indexa o código-fonte em um knowledge graph persistente, expondo
    14 ferramentas MCP para busca semântica, call graph, análise de impacto e arquitetura.

    O codebase-memory-mcp é a evolução plug-and-play da solução de RAG vetorial anterior
    (mcp-vector-search). Diferenças fundamentais:

    - Binário estático único (C puro) — zero dependências (sem Python, sem Node, sem Docker)
    - Modelo de embedding (nomic-embed-code, 768d) compilado no binário — sem download
    - 158 linguagens via tree-sitter vendored — nada para instalar
    - Hybrid LSP para 11 linguagens (Python, TS, Go, Java, Kotlin, C#, Rust, C, C++, PHP)
    - 100% offline desde o primeiro uso — nenhuma conexão de rede necessária após instalação
    - Auto-sync via git-based change detection — índice nunca fica desatualizado
    - Cross-service linking (HTTP, gRPC, GraphQL, pub-sub)
    - Infrastructure-as-code indexing (Dockerfiles, K8s, Kustomize)

    O script realiza:
    1. Download do binário estático para Windows (amd64)
    2. Verificação de checksum SHA-256
    3. Instalação em %LOCALAPPDATA%\Programs\codebase-memory-mcp
    4. Adição ao PATH do usuário (sem admin)
    5. Configuração do mcp.json para GitHub Copilot no IntelliJ
    6. Opcionalmente, indexação inicial do workspace

    Pré-requisitos:
    - Windows 11 (sem necessidade de admin)
    - Conexão com internet (apenas para download do binário, ~15MB)

.PARAMETER WorkspacePath
    Caminho do workspace que será indexado após instalação. Padrão: $env:USERPROFILE\workspace
    Se especificado, executa 'codebase-memory-mcp index' no diretório.

.PARAMETER Scope
    Define o escopo de indexação:
    - 'project': Indexa apenas o WorkspacePath especificado (padrão).
    - 'workspace': Indexa todo o diretório (cross-repository search).

.PARAMETER Variant
    Variante do binário:
    - 'standard': Apenas o motor de code intelligence (padrão, mais leve).
    - 'ui': Inclui visualização 3D do knowledge graph em localhost:9749.

.PARAMETER InstallDir
    Diretório de instalação do binário. Padrão: $env:LOCALAPPDATA\Programs\codebase-memory-mcp

.PARAMETER SkipIndex
    Pula a indexação inicial do workspace (útil para instalação em massa).

.PARAMETER AutoIndex
    Habilita indexação automática ao conectar o MCP server a um novo projeto.

.PARAMETER Uninstall
    Remove o codebase-memory-mcp, configurações MCP e dados do PATH.

.EXAMPLE
    .\scripts\setup-codebase-memory.ps1
    # Instala com valores padrão

.EXAMPLE
    .\scripts\setup-codebase-memory.ps1 -WorkspacePath "C:\projetos\meu-microservico"
    # Instala e indexa um workspace específico

.EXAMPLE
    .\scripts\setup-codebase-memory.ps1 -Scope workspace
    # Indexa todo o diretório de trabalho (cross-repository)

.EXAMPLE
    .\scripts\setup-codebase-memory.ps1 -Variant ui
    # Instala com visualização 3D do knowledge graph

.EXAMPLE
    .\scripts\setup-codebase-memory.ps1 -Uninstall
    # Remove completamente

.NOTES
    Autor: Rodrigo Maneschy
    Versão: 1.0.0
    Compatível com: codebase-memory-mcp (latest release)
    Dependências: Nenhuma (binário estático auto-contido)
    Repositório: https://github.com/DeusData/codebase-memory-mcp
#>

param(
    [string]$WorkspacePath = "$env:USERPROFILE\workspace",
    [ValidateSet("project", "workspace")]
    [string]$Scope = "project",
    [ValidateSet("standard", "ui")]
    [string]$Variant = "standard",
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp",
    [switch]$SkipIndex,
    [switch]$AutoIndex,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Enforce TLS 1.2+ (PowerShell antigo usa TLS 1.0 que GitHub rejeita)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# ═══════════════════════════════════════════════════════════════════════════════
# Constantes
# ═══════════════════════════════════════════════════════════════════════════════
$Repo = "DeusData/codebase-memory-mcp"
$BinName = "codebase-memory-mcp.exe"
$BaseUrl = "https://github.com/$Repo/releases/latest/download"
$BinPath = Join-Path $InstallDir $BinName

# ═══════════════════════════════════════════════════════════════════════════════
# Banner
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  codebase-memory-mcp — Setup Plug-and-Play                  ║" -ForegroundColor Cyan
Write-Host "║  Code Intelligence via Knowledge Graph + MCP                ║" -ForegroundColor Cyan
Write-Host "║  Zero dependências · 158 linguagens · 100% offline          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Modo: Uninstall
# ═══════════════════════════════════════════════════════════════════════════════
if ($Uninstall) {
    Write-Host "  [MODO DESINSTALAÇÃO] Removendo codebase-memory-mcp..." -ForegroundColor Yellow
    Write-Host ""

    # Executar uninstall nativo (remove configs de agentes)
    if (Test-Path $BinPath) {
        try {
            & $BinPath uninstall -y 2>&1 | Out-Null
            Write-Host "    OK: Configurações de agentes removidas." -ForegroundColor DarkGray
        } catch {
            Write-Host "    AVISO: Não foi possível executar uninstall nativo." -ForegroundColor Yellow
        }
    }

    # Remover binário
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    REMOVIDO: $InstallDir" -ForegroundColor DarkGray
    } else {
        Write-Host "    NÃO ENCONTRADO: $InstallDir" -ForegroundColor DarkGray
    }

    # Remover do PATH do usuário
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($UserPath -like "*$InstallDir*") {
        $NewPath = ($UserPath -split ";" | Where-Object { $_ -ne $InstallDir }) -join ";"
        [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
        Write-Host "    REMOVIDO do PATH: $InstallDir" -ForegroundColor DarkGray
    }

    # Remover entrada do mcp.json do IntelliJ
    $McpJsonPath = "$env:USERPROFILE\.config\github-copilot\intellij\mcp.json"
    if (Test-Path $McpJsonPath) {
        try {
            $config = Get-Content $McpJsonPath -Raw | ConvertFrom-Json -AsHashtable
            $removed = $false
            foreach ($key in @("servers", "mcpServers")) {
                if ($config.ContainsKey($key)) {
                    foreach ($serverName in @("codebase-memory", "codebase-memory-mcp")) {
                        if ($config[$key].ContainsKey($serverName)) {
                            $config[$key].Remove($serverName)
                            $removed = $true
                        }
                    }
                }
            }
            if ($removed) {
                $config | ConvertTo-Json -Depth 10 | Set-Content $McpJsonPath -Encoding UTF8
                Write-Host "    REMOVIDO do mcp.json: entrada codebase-memory" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "    AVISO: Não foi possível limpar mcp.json." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  OK: codebase-memory-mcp removido com sucesso." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Nota: Índices locais (.codebase-memory/) nos projetos NÃO foram removidos." -ForegroundColor DarkGray
    Write-Host "  Para remover índices de um projeto específico:" -ForegroundColor DarkGray
    Write-Host "    Remove-Item -Recurse 'C:\seu-projeto\.codebase-memory'" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 1: Verificar se já está instalado e comparar versão
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "  [1/4] Verificando instalação existente..." -ForegroundColor White

$skipDownload = $false
$existingBin = Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue
if ($existingBin) {
    $currentVersion = (& $existingBin.Source --version 2>&1) -replace '[^0-9.]', '' | Select-Object -First 1
    Write-Host "    Versao local: $currentVersion" -ForegroundColor Cyan

    # Consultar versao mais recente via GitHub API (leve, sem download)
    try {
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing -TimeoutSec 10
        $latestVersion = $releaseInfo.tag_name -replace '^v', ''
        Write-Host "    Versao remota: $latestVersion" -ForegroundColor Cyan

        if ($currentVersion -eq $latestVersion) {
            Write-Host "    OK: Ja esta na versao mais recente. Download desnecessario." -ForegroundColor Green
            $skipDownload = $true
        } else {
            Write-Host "    Atualizacao disponivel: $currentVersion -> $latestVersion" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    AVISO: Nao foi possivel consultar versao remota (sem internet?)." -ForegroundColor Yellow
        Write-Host "    Mantendo versao atual instalada." -ForegroundColor Yellow
        $skipDownload = $true
    }
} else {
    Write-Host "    Nenhuma instalacao anterior detectada. Instalacao limpa." -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 2: Download e instalação do binário (skip se já atualizado)
# ═══════════════════════════════════════════════════════════════════════════════
if (-not $skipDownload) {
Write-Host ""
Write-Host "  [2/4] Baixando codebase-memory-mcp ($Variant)..." -ForegroundColor White

# Determinar arquivo de download
if ($Variant -eq "ui") {
    $Archive = "codebase-memory-mcp-ui-windows-amd64.zip"
} else {
    $Archive = "codebase-memory-mcp-windows-amd64.zip"
}
$DownloadUrl = "$BaseUrl/$Archive"

# Criar diretório temporário
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "cbm-install-$(Get-Random)"
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

try {
    # Download do binário
    Write-Host "    URL: $DownloadUrl" -ForegroundColor DarkGray
    Write-Host "    Baixando (~15MB)..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile "$TmpDir\$Archive" -UseBasicParsing

    # Verificação de checksum
    Write-Host "    Verificando integridade (SHA-256)..."
    $ChecksumUrl = "$BaseUrl/checksums.txt"
    try {
        Invoke-WebRequest -Uri $ChecksumUrl -OutFile "$TmpDir\checksums.txt" -UseBasicParsing
        $checksumLine = Get-Content "$TmpDir\checksums.txt" | Where-Object { $_ -like "*$Archive*" }
        if ($checksumLine) {
            $expected = ($checksumLine -split '\s+')[0]
            $actual = (Get-FileHash -Path "$TmpDir\$Archive" -Algorithm SHA256).Hash.ToLower()
            if ($expected -ne $actual) {
                Write-Host ""
                Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
                Write-Host "    │ ERRO: CHECKSUM MISMATCH!                                    │" -ForegroundColor Red
                Write-Host "    │ O arquivo baixado não corresponde ao hash esperado.         │" -ForegroundColor Red
                Write-Host "    │                                                             │" -ForegroundColor Red
                Write-Host "    │ Possíveis causas:                                           │" -ForegroundColor Red
                Write-Host "    │ - Proxy corporativo interceptando o download                │" -ForegroundColor Red
                Write-Host "    │ - Download corrompido                                       │" -ForegroundColor Red
                Write-Host "    │                                                             │" -ForegroundColor Red
                Write-Host "    │ Esperado: $($expected.Substring(0,32))...                   │" -ForegroundColor Red
                Write-Host "    │ Obtido:   $($actual.Substring(0,32))...                     │" -ForegroundColor Red
                Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
                Remove-Item -Recurse -Force $TmpDir
                exit 1
            }
            Write-Host "    OK: Checksum verificado." -ForegroundColor Green
        } else {
            Write-Host "    AVISO: Arquivo não encontrado no checksums.txt (verificação pulada)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    AVISO: Não foi possível verificar checksum (non-fatal)." -ForegroundColor Yellow
    }

    # Extrair
    Write-Host "    Extraindo..."
    Expand-Archive -Path "$TmpDir\$Archive" -DestinationPath $TmpDir -Force

    # Localizar binário extraído
    $DlBin = Join-Path $TmpDir $BinName
    if (-not (Test-Path $DlBin)) {
        # Variante UI pode ter nome diferente
        $UiBin = Join-Path $TmpDir "codebase-memory-mcp-ui.exe"
        if (Test-Path $UiBin) {
            Rename-Item $UiBin $BinName
            $DlBin = Join-Path $TmpDir $BinName
        } else {
            throw "Binário não encontrado após extração."
        }
    }

    # Instalar no diretório de destino
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # Lidar com binário em uso (rename-aside)
    if (Test-Path $BinPath) {
        $OldBin = "$BinPath.old"
        Remove-Item $OldBin -Force -ErrorAction SilentlyContinue
        try {
            Rename-Item $BinPath $OldBin -ErrorAction Stop
        } catch {
            Write-Host "    AVISO: Binário anterior em uso. Tentando sobrescrever..." -ForegroundColor Yellow
        }
    }

    Copy-Item $DlBin $BinPath -Force

    # Verificar instalação
    $installedVersion = & $BinPath --version 2>&1
    Write-Host "    OK: $installedVersion instalado em $InstallDir" -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
    Write-Host "    │ ERRO: Falha no download/instalação.                         │" -ForegroundColor Red
    Write-Host "    ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Red
    Write-Host "    │ Possíveis causas:                                           │" -ForegroundColor Red
    Write-Host "    │ - Sem acesso à internet                                     │" -ForegroundColor Red
    Write-Host "    │ - Proxy corporativo bloqueando github.com                   │" -ForegroundColor Red
    Write-Host "    │ - Firewall bloqueando downloads                             │" -ForegroundColor Red
    Write-Host "    │                                                             │" -ForegroundColor Red
    Write-Host "    │ Alternativa manual:                                         │" -ForegroundColor Red
    Write-Host "    │ 1. Baixe de: github.com/DeusData/codebase-memory-mcp       │" -ForegroundColor Red
    Write-Host "    │    (Releases > Latest > $Archive)                           │" -ForegroundColor Red
    Write-Host "    │ 2. Extraia em: $InstallDir                                  │" -ForegroundColor Red
    Write-Host "    │ 3. Execute novamente este script com -SkipIndex             │" -ForegroundColor Red
    Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
    Write-Host ""
    Write-Host "    Detalhes: $_" -ForegroundColor DarkGray
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
    exit 1
} finally {
    # Limpar temporários
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

} # Fim do if (-not $skipDownload)

# Adicionar ao PATH do usuário (sem admin)
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$InstallDir", "User")
    $env:PATH = "$env:PATH;$InstallDir"
    Write-Host "    Adicionado ao PATH do usuário: $InstallDir" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 3: Configurar MCP para GitHub Copilot no IntelliJ
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [3/4] Configurando integração MCP para IntelliJ Copilot..." -ForegroundColor White

$McpConfigDir = "$env:USERPROFILE\.config\github-copilot\intellij"
$McpJsonPath = Join-Path $McpConfigDir "mcp.json"

# Criar diretório se não existir
if (-not (Test-Path $McpConfigDir)) {
    New-Item -ItemType Directory -Path $McpConfigDir -Force | Out-Null
    Write-Host "    Diretório criado: $McpConfigDir" -ForegroundColor DarkGray
}

# Carregar configuração existente ou criar nova
$mcpConfig = @{}
if (Test-Path $McpJsonPath) {
    try {
        $mcpConfig = Get-Content $McpJsonPath -Raw | ConvertFrom-Json -AsHashtable
        Write-Host "    Configuração MCP existente detectada. Preservando outros servidores." -ForegroundColor Cyan
    } catch {
        Write-Host "    AVISO: mcp.json existente corrompido. Será recriado." -ForegroundColor Yellow
        $mcpConfig = @{}
    }
}

# Garantir que a chave de servidores existe
$serversKey = "servers"
if ($mcpConfig.ContainsKey("mcpServers")) {
    $serversKey = "mcpServers"
} elseif (-not $mcpConfig.ContainsKey("servers")) {
    $mcpConfig["servers"] = @{}
}

# Configurar o servidor codebase-memory-mcp com alias genérico "code-search"
# O binário aceita stdio nativamente — basta apontar o comando
$mcpConfig[$serversKey]["code-search"] = @{
    type    = "stdio"
    command = $BinPath
    args    = @()
}

# Remover servidores antigos (mcp-vector-search e nome literal anterior) se existirem
foreach ($oldServer in @("local-code-rag", "workspace-code-rag", "mcp-vector-search", "vector-search", "codebase-memory")) {
    if ($mcpConfig[$serversKey].ContainsKey($oldServer)) {
        $mcpConfig[$serversKey].Remove($oldServer)
        Write-Host "    Removido servidor legado: $oldServer" -ForegroundColor DarkGray
    }
}

# Salvar configuração
$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content $McpJsonPath -Encoding UTF8
Write-Host "    OK: mcp.json atualizado com servidor 'code-search'" -ForegroundColor Green
Write-Host "    Arquivo: $McpJsonPath" -ForegroundColor DarkGray

# Habilitar auto-index se solicitado
if ($AutoIndex) {
    Write-Host "    Habilitando auto-index..."
    & $BinPath config set auto_index true 2>&1 | Out-Null
    Write-Host "    OK: Auto-index habilitado (projetos serão indexados automaticamente)." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 4: Indexação inicial do workspace (opcional)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [4/4] Indexação do workspace..." -ForegroundColor White

if ($SkipIndex) {
    Write-Host "    SKIP: Indexação pulada (flag -SkipIndex)." -ForegroundColor Yellow
    Write-Host "    O índice será criado automaticamente na primeira busca." -ForegroundColor DarkGray
} elseif (-not (Test-Path $WorkspacePath)) {
    Write-Host "    SKIP: Diretório não encontrado: $WorkspacePath" -ForegroundColor Yellow
    Write-Host "    O índice será criado quando você abrir um projeto e pedir 'Index this project'." -ForegroundColor DarkGray
} else {
    # Determinar diretório de indexação
    $IndexTarget = $WorkspacePath

    if ($Scope -eq "workspace") {
        Write-Host "    Modo: workspace (cross-repository)" -ForegroundColor Cyan
        Write-Host "    Indexando: $IndexTarget" -ForegroundColor Cyan
    } else {
        Write-Host "    Modo: project" -ForegroundColor Cyan
        Write-Host "    Indexando: $IndexTarget" -ForegroundColor Cyan
    }

    Write-Host "    Iniciando indexação (pode levar alguns segundos)..."
    Write-Host ""

    try {
        Push-Location $IndexTarget
        $indexOutput = & $BinPath index 2>&1
        Pop-Location

        if ($LASTEXITCODE -eq 0) {
            Write-Host "    OK: Workspace indexado com sucesso." -ForegroundColor Green
        } else {
            Write-Host "    AVISO: Indexação retornou código $LASTEXITCODE" -ForegroundColor Yellow
            Write-Host "    $indexOutput" -ForegroundColor DarkGray
        }
    } catch {
        Pop-Location -ErrorAction SilentlyContinue
        Write-Host "    AVISO: Falha na indexação inicial (non-fatal)." -ForegroundColor Yellow
        Write-Host "    O índice será criado na primeira busca via Copilot." -ForegroundColor DarkGray
        Write-Host "    Detalhes: $_" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ═══════════════════════════════════════════════════════════════════════════════
$variantDisplay = if ($Variant -eq "ui") { "UI (graph visualization em localhost:9749)" } else { "Standard" }

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  INSTALAÇÃO CONCLUÍDA COM SUCESSO                           ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Componente:  codebase-memory-mcp (Knowledge Graph + MCP)   ║" -ForegroundColor Green
Write-Host "║  Variante:    $($variantDisplay.PadRight(44))║" -ForegroundColor Green
Write-Host "║  Binário:     $($BinPath.Substring(0, [Math]::Min($BinPath.Length, 44)).PadRight(44))║" -ForegroundColor Green
Write-Host "║  MCP Config:  $($McpJsonPath.Substring(0, [Math]::Min($McpJsonPath.Length, 44)).PadRight(44))║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Características:                                           ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  · 158 linguagens (tree-sitter)                             ║" -ForegroundColor Green
Write-Host "║  · Embedding embutido (nomic-embed-code, 768d)              ║" -ForegroundColor Green
Write-Host "║  · 14 MCP tools (search, trace, architecture, impact...)    ║" -ForegroundColor Green
Write-Host "║  · Cross-service linking (HTTP, gRPC, GraphQL)              ║" -ForegroundColor Green
Write-Host "║  · 100% offline (zero dependências externas)                ║" -ForegroundColor Green
Write-Host "║  · Auto-sync via git watcher                                ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Próximos passos:                                           ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  1. Reinicie o IntelliJ IDEA                                ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  2. No Copilot Chat (Agent Mode), verifique se              ║" -ForegroundColor Green
Write-Host "║     'code-search' aparece em Tools                          ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  3. Diga ao agente: 'Index this project'                    ║" -ForegroundColor Green
Write-Host "║     (ou o índice será criado na primeira busca)             ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │ FERRAMENTAS MCP DISPONÍVEIS (14 tools)                     │" -ForegroundColor DarkCyan
Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
Write-Host "  │ search_graph       Busca estrutural (regex, label, degree) │" -ForegroundColor DarkCyan
Write-Host "  │ semantic_query     Busca semântica vetorial (linguagem nat)│" -ForegroundColor DarkCyan
Write-Host "  │ trace_call_path    Call graph (quem chama / é chamado por) │" -ForegroundColor DarkCyan
Write-Host "  │ get_architecture   Visão geral da arquitetura do projeto   │" -ForegroundColor DarkCyan
Write-Host "  │ detect_changes     Impacto de mudanças (git diff → risco)  │" -ForegroundColor DarkCyan
Write-Host "  │ query_graph        Queries Cypher-like no knowledge graph  │" -ForegroundColor DarkCyan
Write-Host "  │ search_code        Grep inteligente (graph-augmented)      │" -ForegroundColor DarkCyan
Write-Host "  │ get_code_snippet   Extrai trecho de código por símbolo     │" -ForegroundColor DarkCyan
Write-Host "  │ manage_adr         Architecture Decision Records (CRUD)    │" -ForegroundColor DarkCyan
Write-Host "  │ ingest_traces      Importar traces de execução             │" -ForegroundColor DarkCyan
Write-Host "  │ ... e mais 4 tools                                         │" -ForegroundColor DarkCyan
Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Dica: Para indexar um projeto manualmente:" -ForegroundColor DarkGray
Write-Host "    cd C:\seu-projeto && codebase-memory-mcp index" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para habilitar auto-index:" -ForegroundColor DarkGray
Write-Host "    codebase-memory-mcp config set auto_index true" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para visualizar o knowledge graph (variante UI):" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-codebase-memory.ps1 -Variant ui" -ForegroundColor DarkGray
Write-Host "    Abra http://localhost:9749 no navegador" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para atualizar para a versão mais recente:" -ForegroundColor DarkGray
Write-Host "    codebase-memory-mcp update" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para compartilhar índice com o time (via git):" -ForegroundColor DarkGray
Write-Host "    git add .codebase-memory/graph.db.zst && git commit" -ForegroundColor DarkGray
Write-Host "    (colegas fazem incremental diff ao invés de full reindex)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para remover completamente:" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-codebase-memory.ps1 -Uninstall" -ForegroundColor DarkGray
Write-Host ""
