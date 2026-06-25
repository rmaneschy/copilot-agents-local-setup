<#
.SYNOPSIS
    [LEGADO] Instala e configura o mcp-vector-search v4.x para busca semântica de código via RAG.

.DESCRIPTION
    [LEGADO] Este script foi substituído pelo setup-codebase-memory.ps1, que é mais simples,
    não requer Python e oferece mais funcionalidades (knowledge graph + busca semântica + call graph).
    Use este script apenas se precisar especificamente do mcp-vector-search por compatibilidade.

    Este script automatiza a instalação independente do mcp-vector-search v4.x, que fornece
    capacidades de busca semântica (RAG - Retrieval Augmented Generation) ao GitHub Copilot
    Agent Mode via protocolo MCP.

    O mcp-vector-search complementa o Serena: enquanto o Serena navega a estrutura
    determinística do código (AST, símbolos, referências), o vector-search encontra
    trechos semanticamente relevantes mesmo sem correspondência exata de nomes.

    MUDANÇA v4.x: O embedding agora é feito localmente via sentence-transformers (Python),
    usando o modelo all-MiniLM-L6-v2 (384 dimensões). NÃO depende mais do Ollama para
    gerar embeddings. O modelo é baixado do HuggingFace na primeira execução e depois
    funciona 100% offline.

    Pré-requisitos:
    - Windows 11 (sem necessidade de admin)
    - Python 3.11+ no PATH

.PARAMETER WorkspacePath
    Caminho do workspace que será indexado. Padrão: $env:USERPROFILE\workspace

.PARAMETER Scope
    Define o escopo de indexação:
    - 'project': Indexa apenas o WorkspacePath especificado (padrão).
    - 'workspace': Indexa todo o diretório pai (~/workspace), permitindo busca cross-repository.
    Quando 'workspace' é selecionado, o mcp-vector-search enxerga todos os projetos
    no diretório de trabalho, possibilitando encontrar quem consome endpoints de outro projeto.

.PARAMETER EmbeddingModel
    Nome do modelo de embedding sentence-transformers. Padrão: sentence-transformers/all-MiniLM-L6-v2
    Outros modelos compatíveis:
    - microsoft/graphcodebert-base (otimizado para código, requer GPU)
    - sentence-transformers/all-mpnet-base-v2 (maior precisão, mais lento)

.PARAMETER Backend
    Backend de inferência para embeddings. Padrão: auto
    - 'auto': ONNX em CPU-only, PyTorch em MPS/CUDA (recomendado)
    - 'onnx': Força ONNX Runtime (mais rápido em CPU, menor consumo de RAM)
    - 'pytorch': Força PyTorch (necessário para GPU)

.PARAMETER VenvPath
    Caminho do ambiente virtual Python. Padrão: $env:USERPROFILE\local-tools\python-venv

.PARAMETER SkipModelDownload
    Pula o download do modelo de embedding (útil se o modelo já está em cache).

.PARAMETER OfflineMode
    Configura o mcp-vector-search para funcionar sem acesso à internet.
    Requer que o modelo já tenha sido baixado previamente (via execução anterior ou cópia manual).

.PARAMETER Uninstall
    Remove o mcp-vector-search, o venv e a configuração MCP associada.

.EXAMPLE
    .\scripts\setup-vector-search.ps1
    # Instala com valores padrão (baixa modelo automaticamente)

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -WorkspacePath "C:\projetos\meu-microservico"
    # Instala apontando para um workspace específico

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -Scope workspace
    # Indexa todo o ~/workspace para busca cross-repository

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -OfflineMode
    # Configura para ambiente corporativo sem internet (modelo deve estar em cache)

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -Backend onnx
    # Força uso do ONNX Runtime (mais leve em CPU)

.EXAMPLE
    .\scripts\setup-vector-search.ps1 -Uninstall
    # Remove a instalação completamente

.NOTES
    Autor: Rodrigo Maneschy
    Versão: 3.0.0
    Compatível com: mcp-vector-search v4.x (>= 4.1.14)
    Dependências: Python 3.11+
    Mudança principal: Não depende mais do Ollama para embeddings.
    Usa sentence-transformers com modelo local (all-MiniLM-L6-v2).
#>

param(
    [string]$WorkspacePath = "$env:USERPROFILE\workspace",
    [ValidateSet("project", "workspace")]
    [string]$Scope = "project",
    [string]$EmbeddingModel = "sentence-transformers/all-MiniLM-L6-v2",
    [ValidateSet("auto", "onnx", "pytorch")]
    [string]$Backend = "auto",
    [string]$VenvPath = "$env:USERPROFILE\local-tools\python-venv",
    [switch]$SkipModelDownload,
    [switch]$OfflineMode,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# ═══════════════════════════════════════════════════════════════════════════════
# Banner
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  mcp-vector-search v4 — Setup Independente                  ║" -ForegroundColor Cyan
Write-Host "║  Busca Semântica de Código via RAG + LanceDB                ║" -ForegroundColor Cyan
Write-Host "║  Embedding: sentence-transformers (local, sem Ollama)       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Constantes
# ═══════════════════════════════════════════════════════════════════════════════
$SentenceTransformersHome = "$env:USERPROFILE\.cache\sentence-transformers"
$HuggingFaceHome = "$env:USERPROFILE\.cache\huggingface"

# ═══════════════════════════════════════════════════════════════════════════════
# Resolução de Escopo (Scope)
# ═══════════════════════════════════════════════════════════════════════════════

# Determinar o caminho efetivo de indexação com base no Scope
$IndexTarget = $WorkspacePath

if ($Scope -eq "workspace") {
    # No modo workspace, indexa o diretório inteiro (todos os projetos)
    # Se WorkspacePath aponta para um subprojeto, sobe para o diretório pai
    if (-not (Test-Path $WorkspacePath)) {
        # Se não existe, assume que é o diretório de workspace padrão
        $IndexTarget = $WorkspacePath
    } else {
        # Verificar se WorkspacePath contém subpastas com .git (indicando multi-repo)
        $gitRepos = Get-ChildItem -Path $WorkspacePath -Directory -Filter ".git" -Recurse -Depth 1 -ErrorAction SilentlyContinue
        if ($gitRepos.Count -gt 0) {
            # Já é um diretório de workspace com múltiplos repos
            $IndexTarget = $WorkspacePath
        } else {
            # Pode ser um projeto individual, subir para o pai
            $parentDir = Split-Path $WorkspacePath -Parent
            $siblingGitRepos = Get-ChildItem -Path $parentDir -Directory | Where-Object {
                Test-Path (Join-Path $_.FullName ".git")
            }
            if ($siblingGitRepos.Count -gt 1) {
                $IndexTarget = $parentDir
                Write-Host "  Scope 'workspace' detectou multi-repo em: $parentDir" -ForegroundColor Cyan
                Write-Host "  Projetos encontrados: $($siblingGitRepos.Count)" -ForegroundColor Cyan
                foreach ($repo in $siblingGitRepos | Select-Object -First 10) {
                    Write-Host "    - $($repo.Name)" -ForegroundColor DarkGray
                }
                if ($siblingGitRepos.Count -gt 10) {
                    Write-Host "    ... e mais $($siblingGitRepos.Count - 10) projetos" -ForegroundColor DarkGray
                }
            } else {
                # Manter o WorkspacePath original
                $IndexTarget = $WorkspacePath
            }
        }
    }

    Write-Host "" 
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │ MODO: WORKSPACE (Cross-Repository Search)                  │" -ForegroundColor Cyan
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Cyan
    Write-Host "  │ O mcp-vector-search indexará TODOS os projetos no          │" -ForegroundColor Cyan
    Write-Host "  │ diretório, permitindo busca cross-repository.              │" -ForegroundColor Cyan
    Write-Host "  │                                                             │" -ForegroundColor Cyan
    Write-Host "  │ Diretório indexado: $(($IndexTarget).Substring(0, [Math]::Min($IndexTarget.Length, 37)).PadRight(37))│" -ForegroundColor Cyan
    Write-Host "  │                                                             │" -ForegroundColor Cyan
    Write-Host "  │ Isso permite perguntar ao Copilot:                         │" -ForegroundColor Cyan
    Write-Host "  │ 'Quais projetos consomem o endpoint POST /api/orders?'     │" -ForegroundColor Cyan
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "  Scope: project (indexa apenas $WorkspacePath)" -ForegroundColor DarkGray
    Write-Host ""
}

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
                    foreach ($serverName in @("local-code-rag", "workspace-code-rag", "mcp-vector-search", "vector-search")) {
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

    # Remover índice no formato v4 (.mcp-vector-search dentro do workspace)
    $IndexPathV4 = Join-Path $WorkspacePath ".mcp-vector-search"
    if (Test-Path $IndexPathV4) {
        Remove-Item -Path $IndexPathV4 -Recurse -Force
        Write-Host "    REMOVIDO: $IndexPathV4 (índice vetorial v4)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  OK: mcp-vector-search removido com sucesso." -ForegroundColor Green
    Write-Host "  Cache de modelos em $SentenceTransformersHome NÃO foi removido." -ForegroundColor DarkGray
    Write-Host "  Para remover modelos: Remove-Item -Recurse '$SentenceTransformersHome'" -ForegroundColor DarkGray
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

# ─────────────────────────────────────────────────────────────────────────────
# Workaround: Windows Long Paths (MAX_PATH 260 chars)
# O pacote 'kuzu' (dependência transitiva do LanceDB) possui caminhos de source
# que excedem 260 caracteres durante a compilação. Ao redirecionar o TMPDIR para
# um caminho curto dentro do perfil do usuário, evitamos o erro:
#   "No such file or directory: C:\Users\...\AppData\Local\Temp\pip_install-***\kuzu-source\..."
# ─────────────────────────────────────────────────────────────────────────────
$shortTmpDir = Join-Path $env:USERPROFILE "tmp"
if (-not (Test-Path $shortTmpDir)) {
    New-Item -ItemType Directory -Path $shortTmpDir -Force | Out-Null
}
$originalTmp = $env:TMPDIR
$originalTemp = $env:TEMP
$originalTmp2 = $env:TMP
$env:TMPDIR = $shortTmpDir
$env:TEMP = $shortTmpDir
$env:TMP = $shortTmpDir
Write-Host "    Workaround Long Paths: TEMP redirecionado para $shortTmpDir" -ForegroundColor DarkGray

Write-Host "    Atualizando pip..."
& $pipExe install --upgrade pip 2>&1 | Out-Null

# Instalar mcp-vector-search v4.x (já inclui sentence-transformers como dependência)
Write-Host "    Instalando pacotes: mcp-vector-search, lancedb..."
Write-Host "    Tentando instalação com wheels pré-compilados..." -ForegroundColor DarkGray
$installOutput = & $pipExe install --only-binary=kuzu "mcp-vector-search>=4.0.0" lancedb 2>&1

if ($LASTEXITCODE -ne 0) {
    # Fallback: tentar sem restrição de binary-only (pode compilar do source)
    Write-Host "    Wheels binários não disponíveis para kuzu. Tentando compilação do source..." -ForegroundColor Yellow
    $installOutput = & $pipExe install "mcp-vector-search>=4.0.0" lancedb 2>&1
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "    ERRO: Falha na instalação de pacotes." -ForegroundColor Red
    Write-Host "    Detalhes:" -ForegroundColor Red
    Write-Host "    $installOutput" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Possíveis causas:" -ForegroundColor Yellow
    Write-Host "      - Windows Long Paths: mesmo com TEMP curto, o caminho pode exceder 260 chars" -ForegroundColor Yellow
    Write-Host "        Solução: Habilitar LongPathsEnabled (requer admin pontual):" -ForegroundColor Yellow
    Write-Host "        reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f" -ForegroundColor DarkGray
    Write-Host "      - Proxy corporativo bloqueando PyPI" -ForegroundColor Yellow
    Write-Host "        Solução:" -ForegroundColor Yellow
    Write-Host "        $pipExe install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org mcp-vector-search lancedb" -ForegroundColor DarkGray
    Write-Host "      - Versão do Python incompatível (requer 3.11+)" -ForegroundColor Yellow
    Write-Host ""
    # Restaurar variáveis de ambiente originais
    $env:TMPDIR = $originalTmp
    $env:TEMP = $originalTemp
    $env:TMP = $originalTmp2
    exit 1
}

# Restaurar variáveis de ambiente originais
$env:TMPDIR = $originalTmp
$env:TEMP = $originalTemp
$env:TMP = $originalTmp2
Write-Host "    Workaround Long Paths: TEMP restaurado para o valor original." -ForegroundColor DarkGray

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
# Etapa 4: Baixar modelo de embedding (sentence-transformers)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [4/5] Configurando modelo de embedding local..." -ForegroundColor White

# Criar diretório de cache se não existir
if (-not (Test-Path $SentenceTransformersHome)) {
    New-Item -ItemType Directory -Path $SentenceTransformersHome -Force | Out-Null
}

if ($SkipModelDownload) {
    Write-Host "    SKIP: Download do modelo ignorado (flag -SkipModelDownload)." -ForegroundColor Yellow
    Write-Host "    Certifique-se de que '$EmbeddingModel' está em cache:" -ForegroundColor Yellow
    Write-Host "    $SentenceTransformersHome" -ForegroundColor DarkGray
} elseif ($OfflineMode) {
    # Verificar se o modelo já está em cache
    $modelCacheName = $EmbeddingModel -replace "/", "_"
    $modelCachePath = Join-Path $SentenceTransformersHome $modelCacheName

    # Verificar também no cache do HuggingFace Hub (formato alternativo)
    $hfModelCacheName = "models--$($EmbeddingModel -replace '/', '--')"
    $hfModelCachePath = Join-Path $HuggingFaceHome "hub\$hfModelCacheName"

    if ((Test-Path $modelCachePath) -or (Test-Path $hfModelCachePath)) {
        Write-Host "    OK: Modelo encontrado em cache local." -ForegroundColor Green
        if (Test-Path $modelCachePath) {
            Write-Host "    Cache: $modelCachePath" -ForegroundColor DarkGray
        } else {
            Write-Host "    Cache: $hfModelCachePath" -ForegroundColor DarkGray
        }
    } else {
        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
        Write-Host "    │ ERRO: Modelo não encontrado em cache (modo offline).        │" -ForegroundColor Red
        Write-Host "    ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Red
        Write-Host "    │ O modo offline requer que o modelo já esteja em cache.      │" -ForegroundColor Red
        Write-Host "    │                                                             │" -ForegroundColor Red
        Write-Host "    │ Opções para resolver:                                       │" -ForegroundColor Red
        Write-Host "    │                                                             │" -ForegroundColor Red
        Write-Host "    │ 1. Execute sem -OfflineMode (com internet) uma vez:         │" -ForegroundColor Red
        Write-Host "    │    .\scripts\setup-vector-search.ps1                        │" -ForegroundColor Red
        Write-Host "    │                                                             │" -ForegroundColor Red
        Write-Host "    │ 2. Copie o cache de outra máquina para:                     │" -ForegroundColor Red
        Write-Host "    │    $SentenceTransformersHome                                │" -ForegroundColor Red
        Write-Host "    │                                                             │" -ForegroundColor Red
        Write-Host "    │ 3. Clone o modelo via git (em máquina com internet):        │" -ForegroundColor Red
        Write-Host "    │    git clone https://huggingface.co/$EmbeddingModel          │" -ForegroundColor Red
        Write-Host "    │    Copie para: $SentenceTransformersHome\$modelCacheName     │" -ForegroundColor Red
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
} else {
    # Baixar modelo (primeira execução — requer internet)
    Write-Host "    Baixando modelo de embedding: $EmbeddingModel" -ForegroundColor White
    Write-Host "    Destino cache: $SentenceTransformersHome" -ForegroundColor DarkGray
    Write-Host "    (Este download ocorre apenas na primeira execução)" -ForegroundColor DarkGray
    Write-Host ""

    # Usar sentence-transformers para baixar e cachear o modelo
    $downloadScript = @"
import os
os.environ['SENTENCE_TRANSFORMERS_HOME'] = r'$SentenceTransformersHome'
from sentence_transformers import SentenceTransformer
model = SentenceTransformer('$EmbeddingModel')
# Testar que o modelo funciona
test_embedding = model.encode(['test embedding generation'])
print(f'OK: Modelo carregado. Dimensão do embedding: {len(test_embedding[0])}')
"@

    $downloadResult = & $pythonExe -c $downloadScript 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    $($downloadResult | Select-Object -Last 1)" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "    │ AVISO: Falha ao baixar modelo de embedding.                 │" -ForegroundColor Yellow
        Write-Host "    ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Yellow
        Write-Host "    │ Possíveis causas:                                           │" -ForegroundColor Yellow
        Write-Host "    │ - Sem acesso à internet / proxy corporativo                 │" -ForegroundColor Yellow
        Write-Host "    │ - HuggingFace bloqueado pelo firewall                       │" -ForegroundColor Yellow
        Write-Host "    │                                                             │" -ForegroundColor Yellow
        Write-Host "    │ O mcp-vector-search tentará baixar na primeira execução.    │" -ForegroundColor Yellow
        Write-Host "    │                                                             │" -ForegroundColor Yellow
        Write-Host "    │ Para ambiente offline, copie o modelo de outra máquina:     │" -ForegroundColor Yellow
        Write-Host "    │   $SentenceTransformersHome                                 │" -ForegroundColor Yellow
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    Detalhes do erro:" -ForegroundColor DarkGray
        Write-Host "    $downloadResult" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    Continuando instalação (modelo será baixado na primeira busca)..." -ForegroundColor Yellow
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

# ─────────────────────────────────────────────────────────────────────────────
# Montar variáveis de ambiente para o servidor MCP
# Variáveis v4.x (prefixo MCP_VECTOR_SEARCH_):
#   - MCP_VECTOR_SEARCH_EMBEDDING_MODEL: modelo sentence-transformers
#   - MCP_VECTOR_SEARCH_BACKEND: onnx | pytorch (auto se não definido)
#   - MCP_VECTOR_SEARCH_WATCH_FILES: true/false
#   - SENTENCE_TRANSFORMERS_HOME: cache local dos modelos
#   - HF_HUB_OFFLINE: 1 = impede downloads do HuggingFace
#   - TRANSFORMERS_OFFLINE: 1 = impede downloads do transformers
#   - TQDM_DISABLE: 1 = suprime barras de progresso (já definido no código)
# ─────────────────────────────────────────────────────────────────────────────
$serverEnv = @{
    SENTENCE_TRANSFORMERS_HOME         = $SentenceTransformersHome
    MCP_VECTOR_SEARCH_WATCH_FILES      = "true"
    TQDM_DISABLE                       = "1"
}

# Definir modelo apenas se não for o padrão (auto-select)
if ($EmbeddingModel -ne "sentence-transformers/all-MiniLM-L6-v2") {
    $serverEnv["MCP_VECTOR_SEARCH_EMBEDDING_MODEL"] = $EmbeddingModel
}

# Definir backend apenas se não for auto
if ($Backend -ne "auto") {
    $serverEnv["MCP_VECTOR_SEARCH_BACKEND"] = $Backend
}

# Modo offline: impedir qualquer tentativa de download
if ($OfflineMode) {
    $serverEnv["HF_HUB_OFFLINE"] = "1"
    $serverEnv["TRANSFORMERS_OFFLINE"] = "1"
}

# Adicionar/atualizar entrada do mcp-vector-search
if ($Scope -eq "workspace") {
    # Modo workspace: registra servidor com escopo amplo (cross-repository)
    $mcpConfig[$serversKey]["workspace-code-rag"] = @{
        type    = "stdio"
        command = $pythonExe
        args    = @("-m", "mcp_vector_search.mcp.server", $IndexTarget)
        env     = $serverEnv
    }

    # Remover servidor antigo de escopo project (se existir) para evitar conflito
    if ($mcpConfig[$serversKey].ContainsKey("local-code-rag")) {
        $mcpConfig[$serversKey].Remove("local-code-rag")
        Write-Host "    Removido servidor 'local-code-rag' (substituído por 'workspace-code-rag')." -ForegroundColor DarkGray
    }

    Write-Host "    Servidor registrado: workspace-code-rag" -ForegroundColor Green
    Write-Host "    Escopo: $IndexTarget (todos os projetos)" -ForegroundColor Green
} else {
    # Modo project: registra servidor com escopo do projeto específico
    $mcpConfig[$serversKey]["local-code-rag"] = @{
        type    = "stdio"
        command = $pythonExe
        args    = @("-m", "mcp_vector_search.mcp.server", $IndexTarget)
        env     = $serverEnv
    }

    # Remover servidor workspace (se existir) para evitar conflito
    if ($mcpConfig[$serversKey].ContainsKey("workspace-code-rag")) {
        $mcpConfig[$serversKey].Remove("workspace-code-rag")
        Write-Host "    Removido servidor 'workspace-code-rag' (substituído por 'local-code-rag')." -ForegroundColor DarkGray
    }

    Write-Host "    Servidor registrado: local-code-rag" -ForegroundColor Green
    Write-Host "    Escopo: $IndexTarget (projeto específico)" -ForegroundColor Green
}

# Salvar configuração
$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content $McpJsonPath -Encoding UTF8
Write-Host "    OK: mcp.json atualizado em $McpJsonPath" -ForegroundColor Green

# Exibir configuração aplicada
Write-Host ""
$serverName = if ($Scope -eq "workspace") { "workspace-code-rag" } else { "local-code-rag" }
$backendDisplay = if ($Backend -eq "auto") { "auto (ONNX em CPU, PyTorch em GPU)" } else { $Backend }
$offlineDisplay = if ($OfflineMode) { "Sim (HF_HUB_OFFLINE=1)" } else { "Não (download permitido)" }

Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │ CONFIGURAÇÃO MCP APLICADA                                   │" -ForegroundColor DarkCyan
Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
Write-Host "  │ Server Name:    $($serverName.PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Scope:          $($Scope.PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Transport:      stdio                                        │" -ForegroundColor DarkCyan
Write-Host "  │ Command:        $($pythonExe.Substring(0, [Math]::Min($pythonExe.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Index Target:   $($IndexTarget.Substring(0, [Math]::Min($IndexTarget.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Embedding:      $($EmbeddingModel.Substring(0, [Math]::Min($EmbeddingModel.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Backend:        $($backendDisplay.Substring(0, [Math]::Min($backendDisplay.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ Offline Mode:   $($offlineDisplay.Substring(0, [Math]::Min($offlineDisplay.Length, 45)).PadRight(45))│" -ForegroundColor DarkCyan
Write-Host "  │ File Watching:  Habilitado                                   │" -ForegroundColor DarkCyan
Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan

# ═══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  INSTALAÇÃO CONCLUÍDA COM SUCESSO                           ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Componente:  mcp-vector-search v4.x (RAG Vetorial)         ║" -ForegroundColor Green
Write-Host "║  Embedding:   sentence-transformers (local, sem Ollama)      ║" -ForegroundColor Green
Write-Host "║  Venv:        $($VenvPath.Substring(0, [Math]::Min($VenvPath.Length, 42)).PadRight(42))║" -ForegroundColor Green
Write-Host "║  MCP Config:  $($McpJsonPath.Substring(0, [Math]::Min($McpJsonPath.Length, 42)).PadRight(42))║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Próximos passos:                                           ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  1. Reinicie o IntelliJ IDEA                                ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  2. No Copilot Chat (Agent Mode), verifique se              ║" -ForegroundColor Green
Write-Host "║     '$($serverName.PadRight(45))' aparece em Tools║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  3. O índice será criado automaticamente na primeira busca  ║" -ForegroundColor Green
Write-Host "║     (file watching mantém o índice atualizado)              ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Dica: Para trocar o workspace indexado:" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -WorkspacePath 'C:\projetos\outro-repo'" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para busca cross-repository (todos os projetos):" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -Scope workspace" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para ambiente offline (após primeiro download):" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -OfflineMode" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para forçar ONNX (mais leve em CPU):" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -Backend onnx" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dica: Para remover completamente:" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup-vector-search.ps1 -Uninstall" -ForegroundColor DarkGray
Write-Host ""
