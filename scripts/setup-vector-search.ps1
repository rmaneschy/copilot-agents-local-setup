<#
.SYNOPSIS
    Instala e configura o mcp-vector-search para busca semântica de código via RAG.

.DESCRIPTION
    Este script automatiza a instalação independente do mcp-vector-search, que fornece
    capacidades de busca semântica (RAG - Retrieval Augmented Generation) ao GitHub Copilot
    Agent Mode via protocolo MCP.

    O mcp-vector-search complementa o Serena: enquanto o Serena navega a estrutura
    determinística do código (AST, símbolos, referências), o vector-search encontra
    trechos semanticamente relevantes mesmo sem correspondência exata de nomes.

    Pré-requisitos:
    - Windows 11 (sem necessidade de admin)
    - Python 3.11+ no PATH
    - Ollama rodando com modelo de embedding disponível

.PARAMETER WorkspacePath
    Caminho do workspace que será indexado. Padrão: $env:USERPROFILE\workspace

.PARAMETER EmbeddingModel
    Nome do modelo de embedding no Ollama. Padrão: nomic-embed-text

.PARAMETER OllamaUrl
    URL base do Ollama. Padrão: http://localhost:11434

.PARAMETER VenvPath
    Caminho do ambiente virtual Python. Padrão: $env:USERPROFILE\local-tools\python-venv

.PARAMETER SkipOllamaCheck
    Pula a verificação de conectividade com o Ollama (útil se o Ollama será instalado depois).

.PARAMETER Uninstall
    Remove o mcp-vector-search, o venv e a configuração MCP associada.

.EXAMPLE
    .\scripts\setup-vector-search.ps1
    # Instala com valores padrão

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -WorkspacePath "C:\projetos\meu-microservico"
    # Instala apontando para um workspace específico

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -EmbeddingModel "mxbai-embed-large"
    # Usa um modelo de embedding diferente

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -Uninstall
    # Remove a instalação completamente

.NOTES
    Autor: Rodrigo Maneschy
    Versão: 1.0.0
    Dependências: Python 3.11+, Ollama (com modelo de embedding)
#>

param(
    [string]$WorkspacePath = "$env:USERPROFILE\workspace",
    [string]$EmbeddingModel = "nomic-embed-text",
    [string]$OllamaUrl = "http://localhost:11434",
    [string]$VenvPath = "$env:USERPROFILE\local-tools\python-venv",
    [switch]$SkipOllamaCheck,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# ═══════════════════════════════════════════════════════════════════════════════
# Banner
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  mcp-vector-search — Setup Independente                     ║" -ForegroundColor Cyan
Write-Host "║  Busca Semântica de Código via RAG + LanceDB                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Modo: Uninstall
# ═══════════════════════════════════════════════════════════════════════════════
if ($Uninstall) {
    Write-Host "  [MODO DESINSTALAÇÃO] Removendo mcp-vector-search..." -ForegroundColor Yellow
    Write-Host ""

    # Remover venv
    if (Test-Path $VenvPath) {
        Remove-Item -Path $VenvPath -Recurse -Force
        Write-Host "    REMOVIDO: $VenvPath" -ForegroundColor DarkGray
    } else {
        Write-Host "    NÃO ENCONTRADO: $VenvPath" -ForegroundColor DarkGray
    }

    # Remover entrada do mcp.json
    $McpJsonPath = "$env:USERPROFILE\.config\github-copilot\intellij\mcp.json"
    if (Test-Path $McpJsonPath) {
        try {
            $config = Get-Content $McpJsonPath -Raw | ConvertFrom-Json
            $configHash = $config | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

            # Tentar remover de "servers" ou "mcpServers"
            $removed = $false
            foreach ($key in @("servers", "mcpServers")) {
                if ($configHash.ContainsKey($key)) {
                    foreach ($serverName in @("local-code-rag", "mcp-vector-search", "vector-search")) {
                        if ($configHash[$key].ContainsKey($serverName)) {
                            $configHash[$key].Remove($serverName)
                            $removed = $true
                            Write-Host "    REMOVIDO do mcp.json: $key.$serverName" -ForegroundColor DarkGray
                        }
                    }
                }
            }

            if ($removed) {
                $configHash | ConvertTo-Json -Depth 10 | Set-Content $McpJsonPath -Encoding UTF8
            }
        } catch {
            Write-Host "    AVISO: Não foi possível limpar mcp.json automaticamente." -ForegroundColor Yellow
        }
    }

    # Remover índice vetorial
    $IndexPath = "$env:USERPROFILE\.local\share\mcp-vector-search"
    if (Test-Path $IndexPath) {
        Remove-Item -Path $IndexPath -Recurse -Force
        Write-Host "    REMOVIDO: $IndexPath (índice vetorial)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  OK: mcp-vector-search removido com sucesso." -ForegroundColor Green
    Write-Host "  O Ollama e seus modelos NÃO foram afetados." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 1: Verificar Python
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "  [1/5] Verificando Python..." -ForegroundColor White

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    # Tentar python3
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
}

if (-not $pythonCmd) {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
    Write-Host "  │ ERRO: Python não encontrado no PATH.                        │" -ForegroundColor Red
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Red
    Write-Host "  │ Opções de instalação (sem admin):                           │" -ForegroundColor Red
    Write-Host "  │                                                             │" -ForegroundColor Red
    Write-Host "  │ 1. Microsoft Store:                                         │" -ForegroundColor Red
    Write-Host "  │    winget install Python.Python.3.12                        │" -ForegroundColor Red
    Write-Host "  │                                                             │" -ForegroundColor Red
    Write-Host "  │ 2. Standalone (portátil):                                   │" -ForegroundColor Red
    Write-Host "  │    https://www.python.org/ftp/python/3.12.0/                │" -ForegroundColor Red
    Write-Host "  │    Baixe 'python-3.12.x-embed-amd64.zip'                   │" -ForegroundColor Red
    Write-Host "  │                                                             │" -ForegroundColor Red
    Write-Host "  │ 3. Via uv (se já tiver uv instalado):                       │" -ForegroundColor Red
    Write-Host "  │    uv python install 3.12                                   │" -ForegroundColor Red
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
    Write-Host ""
    exit 1
}

$pythonVersion = & $pythonCmd.Source --version 2>&1
Write-Host "    OK: $pythonVersion ($($pythonCmd.Source))" -ForegroundColor Green

# Verificar versão mínima (3.11)
$versionMatch = $pythonVersion | Select-String -Pattern "(\d+)\.(\d+)"
if ($versionMatch) {
    $major = [int]$versionMatch.Matches[0].Groups[1].Value
    $minor = [int]$versionMatch.Matches[0].Groups[2].Value
    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 11)) {
        Write-Host "    AVISO: Python 3.11+ recomendado (encontrado: $major.$minor)." -ForegroundColor Yellow
        Write-Host "    O mcp-vector-search pode não funcionar corretamente." -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 2: Criar ambiente virtual
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [2/5] Configurando ambiente virtual Python..." -ForegroundColor White

$venvCreated = $false
if (Test-Path $VenvPath) {
    Write-Host "    Venv existente encontrado: $VenvPath" -ForegroundColor Green

    # Verificar se o venv está funcional
    $pipPath = Join-Path $VenvPath "Scripts\pip.exe"
    if (-not (Test-Path $pipPath)) {
        Write-Host "    AVISO: Venv corrompido (pip não encontrado). Recriando..." -ForegroundColor Yellow
        Remove-Item -Path $VenvPath -Recurse -Force
        $venvCreated = $false
    } else {
        $venvCreated = $true
    }
}

if (-not $venvCreated) {
    Write-Host "    Criando ambiente virtual em: $VenvPath"

    # Criar diretório pai se não existir
    $parentDir = Split-Path $VenvPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    & $pythonCmd.Source -m venv $VenvPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ERRO: Falha ao criar ambiente virtual." -ForegroundColor Red
        exit 1
    }
    Write-Host "    OK: Ambiente virtual criado." -ForegroundColor Green
}

$pipExe = Join-Path $VenvPath "Scripts\pip.exe"
$pythonExe = Join-Path $VenvPath "Scripts\python.exe"

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 3: Instalar mcp-vector-search e dependências
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [3/5] Instalando mcp-vector-search e dependências..." -ForegroundColor White

Write-Host "    Atualizando pip..."
& $pipExe install --upgrade pip 2>&1 | Out-Null

Write-Host "    Instalando pacotes: mcp-vector-search, lancedb, ollama..."
$installOutput = & $pipExe install mcp-vector-search lancedb ollama 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "    ERRO: Falha na instalação de pacotes." -ForegroundColor Red
    Write-Host "    Detalhes:" -ForegroundColor Red
    Write-Host "    $installOutput" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Possíveis causas:" -ForegroundColor Yellow
    Write-Host "      - Proxy corporativo bloqueando PyPI" -ForegroundColor Yellow
    Write-Host "      - Versão do Python incompatível" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Solução para proxy:" -ForegroundColor Yellow
    Write-Host "      $pipExe install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org mcp-vector-search lancedb" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

# Verificar instalação
$mcpVsVersion = & $pythonExe -c "import mcp_vector_search; print(mcp_vector_search.__version__)" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    OK: mcp-vector-search v$mcpVsVersion instalado." -ForegroundColor Green
} else {
    # Tentar verificar de outra forma
    $installed = & $pipExe show mcp-vector-search 2>&1
    if ($installed -match "Version: (.+)") {
        Write-Host "    OK: mcp-vector-search $($Matches[1]) instalado." -ForegroundColor Green
    } else {
        Write-Host "    OK: Pacotes instalados (versão não verificável)." -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 4: Verificar conectividade com Ollama
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [4/5] Verificando Ollama e modelo de embedding..." -ForegroundColor White

if ($SkipOllamaCheck) {
    Write-Host "    SKIP: Verificação do Ollama ignorada (flag -SkipOllamaCheck)." -ForegroundColor Yellow
    Write-Host "    Certifique-se de que o Ollama esteja rodando com o modelo '$EmbeddingModel' antes de usar." -ForegroundColor Yellow
} else {
    # Verificar se Ollama está respondendo
    $ollamaOnline = $false
    try {
        $response = Invoke-WebRequest -Uri "$OllamaUrl/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
        $ollamaOnline = $true
        Write-Host "    OK: Ollama respondendo em $OllamaUrl" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "    │ AVISO: Ollama não está respondendo em $($OllamaUrl.PadRight(20))│" -ForegroundColor Yellow
        Write-Host "    ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Yellow
        Write-Host "    │ O mcp-vector-search foi instalado, mas precisa do Ollama    │" -ForegroundColor Yellow
        Write-Host "    │ rodando para funcionar. Inicie o Ollama com:                │" -ForegroundColor Yellow
        Write-Host "    │                                                             │" -ForegroundColor Yellow
        Write-Host "    │   ollama serve                                              │" -ForegroundColor Yellow
        Write-Host "    │                                                             │" -ForegroundColor Yellow
        Write-Host "    │ Ou execute o setup completo:                                │" -ForegroundColor Yellow
        Write-Host "    │   .\scripts\setup.ps1                                       │" -ForegroundColor Yellow
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""
    }

    # Verificar se o modelo de embedding está disponível
    if ($ollamaOnline) {
        try {
            $tagsResponse = Invoke-WebRequest -Uri "$OllamaUrl/api/tags" -Method GET -TimeoutSec 5 -ErrorAction Stop
            $models = ($tagsResponse.Content | ConvertFrom-Json).models

            $modelFound = $models | Where-Object { $_.name -match $EmbeddingModel }
            if ($modelFound) {
                Write-Host "    OK: Modelo '$EmbeddingModel' disponível no Ollama." -ForegroundColor Green
            } else {
                Write-Host ""
                Write-Host "    AVISO: Modelo '$EmbeddingModel' não encontrado no Ollama." -ForegroundColor Yellow
                Write-Host "    Modelos disponíveis:" -ForegroundColor White
                foreach ($m in $models) {
                    Write-Host "      - $($m.name)" -ForegroundColor DarkGray
                }
                Write-Host ""
                Write-Host "    Para baixar o modelo:" -ForegroundColor White
                Write-Host "      ollama pull $EmbeddingModel" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "    Ou execute o setup.ps1 que faz o download automaticamente:" -ForegroundColor White
                Write-Host "      .\scripts\setup.ps1 -SkipOllamaTweaks" -ForegroundColor Cyan
                Write-Host ""
            }
        } catch {
            Write-Host "    AVISO: Não foi possível verificar modelos disponíveis." -ForegroundColor Yellow
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 5: Configurar MCP no IntelliJ (GitHub Copilot)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [5/5] Configurando integração MCP para IntelliJ Copilot..." -ForegroundColor White

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

# Garantir que a chave de servidores existe (suportar ambos os formatos)
$serversKey = "servers"
if ($mcpConfig.ContainsKey("mcpServers")) {
    $serversKey = "mcpServers"
} elseif (-not $mcpConfig.ContainsKey("servers")) {
    $mcpConfig["servers"] = @{}
}

# Adicionar/atualizar entrada do mcp-vector-search
$mcpConfig[$serversKey]["local-code-rag"] = @{
    type    = "stdio"
    command = $pythonExe
    args    = @("-m", "mcp_vector_search.mcp.server", $WorkspacePath)
    env     = @{
        MCP_ENABLE_FILE_WATCHING = "true"
        EMBEDDING_MODEL          = $EmbeddingModel
        OLLAMA_BASE_URL          = $OllamaUrl
    }
}

# Salvar configuração
$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content $McpJsonPath -Encoding UTF8
Write-Host "    OK: mcp.json atualizado em $McpJsonPath" -ForegroundColor Green

# Exibir configuração aplicada
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │ CONFIGURAÇÃO MCP APLICADA                                   │" -ForegroundColor DarkCyan
Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
Write-Host "  │ Server Name:    local-code-rag                              │" -ForegroundColor DarkCyan
Write-Host "  │ Transport:      stdio                                       │" -ForegroundColor DarkCyan
Write-Host "  │ Command:        $($pythonExe.Substring(0, [Math]::Min($pythonExe.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Workspace:      $($WorkspacePath.Substring(0, [Math]::Min($WorkspacePath.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Embedding:      $($EmbeddingModel.PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Ollama URL:     $($OllamaUrl.PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ File Watching:  Habilitado                                  │" -ForegroundColor DarkCyan
Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan

# ═══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  INSTALAÇÃO CONCLUÍDA COM SUCESSO                           ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Componente:  mcp-vector-search (RAG Vetorial)               ║" -ForegroundColor Green
Write-Host "║  Venv:        $($VenvPath.Substring(0, [Math]::Min($VenvPath.Length, 42)).PadRight(42))║" -ForegroundColor Green
Write-Host "║  MCP Config:  $($McpJsonPath.Substring(0, [Math]::Min($McpJsonPath.Length, 42)).PadRight(42))║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Próximos passos:                                           ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  1. Certifique-se de que o Ollama está rodando:             ║" -ForegroundColor Green
Write-Host "║     ollama serve                                             ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  2. Baixe o modelo de embedding (se ainda não tem):         ║" -ForegroundColor Green
Write-Host "║     ollama pull $($EmbeddingModel.PadRight(41))║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  3. Indexe o workspace:                                     ║" -ForegroundColor Green
Write-Host "║     .\scripts\index-workspace.ps1                           ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  4. Reinicie o IntelliJ IDEA                                ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  5. No Copilot Chat (Agent Mode), verifique se              ║" -ForegroundColor Green
Write-Host "║     'local-code-rag' aparece em Tools                       ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Dica: Para trocar o workspace indexado:" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -WorkspacePath 'C:\projetos\outro-repo'" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para remover completamente:" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -Uninstall" -ForegroundColor DarkGray
Write-Host ""
