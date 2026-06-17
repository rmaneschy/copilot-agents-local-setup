<#
.SYNOPSIS
Script de configuração do RAG local para código-fonte no Windows (Sem Admin, Sem Docker).

.DESCRIPTION
Este script realiza o download e configuração do Ollama, instala o Python (se necessário),
configura o ambiente virtual e instala o servidor MCP mcp-vector-search.

Em ambientes corporativos com proxy que realiza inspeção de pacotes (SSL/TLS interception),
o comando 'ollama pull' falha na verificação de SHA256 digest. Este script contorna o
problema baixando o modelo GGUF diretamente do HuggingFace e importando-o manualmente
no Ollama via Modelfile.

.PARAMETER SkipModelDownload
Pula o download do modelo de embedding. Útil se o modelo já foi baixado manualmente.

.PARAMETER ModelPath
Caminho para um arquivo GGUF já baixado manualmente. Quando informado, o script usa
este arquivo em vez de tentar baixar do HuggingFace.

.PARAMETER UseOllamaPull
Tenta usar 'ollama pull' diretamente (funciona apenas fora de proxy com inspeção de pacotes).
#>

param(
    [switch]$SkipModelDownload,
    [string]$ModelPath = "",
    [switch]$UseOllamaPull
)

$ErrorActionPreference = "Stop"

$WorkspaceDir = "$HOME\workspace"
$ToolsDir = "$HOME\local-tools"
$OllamaDir = "$ToolsDir\ollama"
$ModelsDir = "$ToolsDir\models"
$PythonVenvDir = "$ToolsDir\mcp-venv"

# Configuração do modelo de embedding
$ModelName = "nomic-embed-text"
$ModelFileName = "nomic-embed-text-v1.5.Q2_K.gguf"
$HuggingFaceUrl = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q2_K.gguf?download=true"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RAG Local Setup - Inteligência de Código                   ║" -ForegroundColor Cyan
Write-Host "║  Compatível com proxy corporativo (SSL inspection)          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# 1. Criar diretórios
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[1/5] Criando diretórios..." -ForegroundColor White
@($ToolsDir, $OllamaDir, $ModelsDir) | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null }
}
Write-Host "  OK: Diretórios criados em $ToolsDir" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 2. Verificar Ollama
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[2/5] Verificando Ollama..." -ForegroundColor White
if (!(Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "  ATENÇÃO: Ollama não encontrado no PATH." -ForegroundColor Yellow
    Write-Host "  Instale o Ollama de: https://ollama.com/download/windows" -ForegroundColor Yellow
    Write-Host "  (A instalação padrão NÃO requer permissões de administrador)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Após instalar, execute este script novamente." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "  OK: Ollama encontrado." -ForegroundColor Green
}

# Iniciar Ollama em background se não estiver rodando
$OllamaProcess = Get-Process ollama -ErrorAction SilentlyContinue
if (!$OllamaProcess) {
    Write-Host "  Iniciando Ollama em background..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

# Verificar se Ollama está respondendo
try {
    $null = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  OK: Ollama respondendo em localhost:11434" -ForegroundColor Green
} catch {
    Write-Host "  AVISO: Ollama não respondeu. Verifique se o serviço está rodando." -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. Baixar e importar modelo de embedding
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[3/5] Configurando modelo de embedding ($ModelName)..." -ForegroundColor White

if ($SkipModelDownload) {
    Write-Host "  SKIP: Download do modelo ignorado (flag -SkipModelDownload)." -ForegroundColor Yellow
} elseif ($UseOllamaPull) {
    # Método padrão: funciona apenas sem proxy com inspeção de pacotes
    Write-Host "  Tentando 'ollama pull' (modo direto, sem proxy)..."
    try {
        ollama pull $ModelName
        Write-Host "  OK: Modelo baixado via ollama pull." -ForegroundColor Green
    } catch {
        Write-Host "  ERRO: 'ollama pull' falhou (provável proxy com inspeção SSL)." -ForegroundColor Red
        Write-Host "  Execute novamente SEM o flag -UseOllamaPull para usar o método HuggingFace." -ForegroundColor Yellow
        exit 1
    }
} else {
    # Método corporativo: download via HuggingFace + importação manual
    $LocalModelPath = "$ModelsDir\$ModelFileName"

    if ($ModelPath -ne "" -and (Test-Path $ModelPath)) {
        # Usuário forneceu o arquivo manualmente
        Write-Host "  Usando modelo fornecido: $ModelPath"
        $LocalModelPath = $ModelPath
    } elseif (Test-Path $LocalModelPath) {
        Write-Host "  Modelo já existe em: $LocalModelPath" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "  │ DOWNLOAD DO MODELO VIA HUGGINGFACE                          │" -ForegroundColor Yellow
        Write-Host "  │                                                             │" -ForegroundColor Yellow
        Write-Host "  │ Em ambientes com proxy corporativo, o 'ollama pull' falha   │" -ForegroundColor Yellow
        Write-Host "  │ na verificação SHA256. Vamos baixar diretamente do          │" -ForegroundColor Yellow
        Write-Host "  │ HuggingFace (que passa pelo proxy sem problemas).           │" -ForegroundColor Yellow
        Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Baixando de: $HuggingFaceUrl"
        Write-Host "  Destino: $LocalModelPath"
        Write-Host "  (Aproximadamente 100 MB - aguarde...)" -ForegroundColor Cyan

        try {
            # Usar .NET WebClient que respeita as configurações de proxy do sistema
            $webClient = New-Object System.Net.WebClient
            $webClient.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
            $webClient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $webClient.DownloadFile($HuggingFaceUrl, $LocalModelPath)
            Write-Host "  OK: Download concluído." -ForegroundColor Green
        } catch {
            Write-Host ""
            Write-Host "  ERRO: Download automático falhou." -ForegroundColor Red
            Write-Host ""
            Write-Host "  SOLUÇÃO MANUAL:" -ForegroundColor Yellow
            Write-Host "  1. Abra no navegador:" -ForegroundColor White
            Write-Host "     $HuggingFaceUrl" -ForegroundColor Cyan
            Write-Host "  2. Salve o arquivo em:" -ForegroundColor White
            Write-Host "     $LocalModelPath" -ForegroundColor Cyan
            Write-Host "  3. Execute novamente:" -ForegroundColor White
            Write-Host "     .\setup.ps1 -ModelPath `"$LocalModelPath`"" -ForegroundColor Cyan
            Write-Host ""
            exit 1
        }
    }

    # Criar Modelfile e importar no Ollama
    Write-Host "  Importando modelo no Ollama via Modelfile..."
    $ModelfileDir = "$ModelsDir\modelfiles"
    if (!(Test-Path $ModelfileDir)) { New-Item -ItemType Directory -Path $ModelfileDir | Out-Null }

    $ModelfilePath = "$ModelfileDir\Modelfile-nomic-embed-text"
    $ModelfileContent = @"
# Modelfile para nomic-embed-text importado do HuggingFace
# Contorna o problema de SHA256 digest em proxies corporativos
FROM $LocalModelPath
"@
    $ModelfileContent | Out-File -FilePath $ModelfilePath -Encoding UTF8 -NoNewline

    try {
        ollama create $ModelName -f $ModelfilePath
        Write-Host "  OK: Modelo '$ModelName' importado com sucesso no Ollama." -ForegroundColor Green
    } catch {
        Write-Host "  ERRO: Falha ao importar modelo no Ollama." -ForegroundColor Red
        Write-Host "  Verifique se o Ollama está rodando: ollama serve" -ForegroundColor Yellow
        exit 1
    }
}

# Verificar se o modelo está disponível
Write-Host "  Verificando modelo..."
$models = ollama list 2>&1
if ($models -match $ModelName) {
    Write-Host "  OK: Modelo '$ModelName' disponível." -ForegroundColor Green
} else {
    Write-Host "  AVISO: Modelo '$ModelName' não encontrado na lista. Verifique manualmente com 'ollama list'." -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. Configurar Python e mcp-vector-search
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[4/5] Configurando Python e mcp-vector-search..." -ForegroundColor White

if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "  ERRO: Python não encontrado." -ForegroundColor Red
    Write-Host "  Instale via Microsoft Store (não requer admin) ou baixe o standalone." -ForegroundColor Yellow
    exit 1
}

if (!(Test-Path $PythonVenvDir)) {
    Write-Host "  Criando ambiente virtual..."
    python -m venv $PythonVenvDir
}

Write-Host "  Instalando dependências (pip, mcp-vector-search, lancedb)..."
& "$PythonVenvDir\Scripts\pip.exe" install --upgrade pip 2>&1 | Out-Null
& "$PythonVenvDir\Scripts\pip.exe" install mcp-vector-search lancedb 2>&1 | Out-Null
Write-Host "  OK: mcp-vector-search instalado." -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 5. Configurar integração com IntelliJ (mcp.json)
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[5/5] Configurando integração MCP para IntelliJ Copilot..." -ForegroundColor White

$IntelliJMcpDir = "$HOME\.config\github-copilot\intellij"
if (!(Test-Path $IntelliJMcpDir)) {
    New-Item -ItemType Directory -Path $IntelliJMcpDir -Force | Out-Null
}

$McpJsonPath = "$IntelliJMcpDir\mcp.json"

# Preservar configurações existentes se houver
$existingConfig = @{}
if (Test-Path $McpJsonPath) {
    try {
        $existingConfig = Get-Content $McpJsonPath -Raw | ConvertFrom-Json -AsHashtable
        Write-Host "  Configuração MCP existente detectada. Será preservada." -ForegroundColor Cyan
    } catch {
        $existingConfig = @{}
    }
}

if (-not $existingConfig.ContainsKey("mcpServers")) {
    $existingConfig["mcpServers"] = @{}
}

$existingConfig["mcpServers"]["local-code-rag"] = @{
    command = "$PythonVenvDir\Scripts\python.exe"
    args = @("-m", "mcp_vector_search.mcp.server", $WorkspaceDir)
    env = @{
        MCP_ENABLE_FILE_WATCHING = "true"
        EMBEDDING_MODEL = $ModelName
        OLLAMA_BASE_URL = "http://localhost:11434"
    }
}

$existingConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $McpJsonPath -Encoding UTF8
Write-Host "  OK: mcp.json atualizado em $McpJsonPath" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# Resumo final
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  CONFIGURAÇÃO CONCLUÍDA COM SUCESSO                         ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Próximos passos:                                           ║" -ForegroundColor Green
Write-Host "║  1. Indexar o workspace:                                    ║" -ForegroundColor Green
Write-Host "║     .\scripts\index-workspace.ps1                           ║" -ForegroundColor Green
Write-Host "║  2. Reiniciar o IntelliJ IDEA                               ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
