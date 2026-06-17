<#
.SYNOPSIS
Script de configuração do RAG local para código-fonte no Windows (Sem Admin, Sem Docker).

.DESCRIPTION
Este script realiza o download e configuração do Ollama, instala o Python (se necessário),
configura o ambiente virtual e instala o servidor MCP mcp-vector-search.
#>

$ErrorActionPreference = "Stop"

$WorkspaceDir = "$HOME\workspace"
$ToolsDir = "$HOME\local-tools"
$OllamaDir = "$ToolsDir\ollama"
$PythonVenvDir = "$ToolsDir\mcp-venv"

Write-Host "Iniciando configuração do RAG Local..." -ForegroundColor Cyan

# 1. Criar diretórios
if (!(Test-Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir | Out-Null }
if (!(Test-Path $OllamaDir)) { New-Item -ItemType Directory -Path $OllamaDir | Out-Null }

# 2. Baixar Ollama (Standalone Windows zip)
Write-Host "Verificando Ollama..."
if (!(Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host "Ollama não encontrado no PATH. Por favor, baixe o instalador do Windows em https://ollama.com/download/windows e instale-o. A instalação padrão não requer permissões de administrador." -ForegroundColor Yellow
    # Alternativa: tentar baixar o binário diretamente se existir link direto
} else {
    Write-Host "Ollama já instalado." -ForegroundColor Green
}

# Iniciar Ollama em background se não estiver rodando
$OllamaProcess = Get-Process ollama -ErrorAction SilentlyContinue
if (!$OllamaProcess) {
    Write-Host "Iniciando Ollama em background..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

# Baixar modelo de embedding leve
Write-Host "Baixando modelo de embedding (nomic-embed-text)..."
ollama pull nomic-embed-text

# 3. Configurar Python e mcp-vector-search
Write-Host "Verificando Python..."
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: Python não encontrado. Instale o Python da Microsoft Store (não requer admin) ou baixe o instalador standalone." -ForegroundColor Red
    exit 1
}

Write-Host "Configurando ambiente virtual Python..."
if (!(Test-Path $PythonVenvDir)) {
    python -m venv $PythonVenvDir
}

# Ativar venv e instalar mcp-vector-search
Write-Host "Instalando mcp-vector-search e dependências..."
& "$PythonVenvDir\Scripts\pip.exe" install --upgrade pip
& "$PythonVenvDir\Scripts\pip.exe" install mcp-vector-search lancedb

# 4. Configurar integração com IntelliJ (mcp.json)
Write-Host "Configurando integração MCP para IntelliJ Copilot..."
$IntelliJMcpDir = "$HOME\.config\github-copilot\intellij"
if (!(Test-Path $IntelliJMcpDir)) {
    New-Item -ItemType Directory -Path $IntelliJMcpDir -Force | Out-Null
}

$McpJsonPath = "$IntelliJMcpDir\mcp.json"
$McpConfig = @{
    mcpServers = @{
        "local-code-rag" = @{
            command = "$PythonVenvDir\Scripts\python.exe"
            args = @("-m", "mcp_vector_search.mcp.server", "$WorkspaceDir")
            env = @{
                MCP_ENABLE_FILE_WATCHING = "true"
                EMBEDDING_MODEL = "nomic-embed-text"
                OLLAMA_BASE_URL = "http://localhost:11434"
            }
        }
    }
}

$McpConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $McpJsonPath -Encoding UTF8
Write-Host "Arquivo mcp.json criado em $McpJsonPath" -ForegroundColor Green

Write-Host "Configuração concluída com sucesso!" -ForegroundColor Green
Write-Host "Para indexar seu workspace inicial, execute:" -ForegroundColor Cyan
Write-Host "& '$PythonVenvDir\Scripts\mcp-vector-search.exe' index --path $WorkspaceDir"
Write-Host "Reinicie seu IntelliJ IDEA para que o Copilot carregue o novo servidor MCP." -ForegroundColor Yellow
