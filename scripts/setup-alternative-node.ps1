<#
.SYNOPSIS
Script de configuração alternativa usando codebase-rag (Node.js/Bun).

.DESCRIPTION
Esta alternativa utiliza o projeto codebase-rag (baseado em Bun/Node.js) que não requer
Ollama para embeddings (usa o modelo ONNX all-MiniLM-L6-v2 embutido).
Ideal para máquinas com recursos mais limitados ou quando não se deseja instalar o Ollama.

Requisitos:
- Node.js 18+ (pode ser instalado via nvm-windows sem admin)
- OU Bun (https://bun.sh - instalação sem admin)
#>

$ErrorActionPreference = "Stop"

$WorkspaceDir = "$HOME\workspace"
$ToolsDir = "$HOME\local-tools"
$CodebaseRagDir = "$ToolsDir\codebase-rag"

Write-Host "=== Setup Alternativo: codebase-rag (Node.js) ===" -ForegroundColor Cyan

# 1. Verificar Node.js ou Bun
$Runtime = $null
if (Get-Command bun -ErrorAction SilentlyContinue) {
    $Runtime = "bun"
    Write-Host "Runtime detectado: Bun" -ForegroundColor Green
} elseif (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVersion = node --version
    Write-Host "Runtime detectado: Node.js $nodeVersion" -ForegroundColor Green
    $Runtime = "npx"
} else {
    Write-Host "ERRO: Nem Node.js nem Bun foram encontrados." -ForegroundColor Red
    Write-Host "Instale o Node.js via nvm-windows (https://github.com/coreybutler/nvm-windows) ou Bun (https://bun.sh)." -ForegroundColor Yellow
    exit 1
}

# 2. Clonar codebase-rag
if (!(Test-Path $CodebaseRagDir)) {
    Write-Host "Clonando codebase-rag..."
    git clone https://github.com/joinQuantish/codebase-rag.git $CodebaseRagDir
} else {
    Write-Host "codebase-rag já existe. Atualizando..."
    Push-Location $CodebaseRagDir
    git pull
    Pop-Location
}

# 3. Instalar dependências
Push-Location $CodebaseRagDir
if ($Runtime -eq "bun") {
    bun install
} else {
    npm install
}
Pop-Location

# 4. Indexar workspace (projetos locais)
Write-Host "Indexando projetos do workspace..."
$projects = Get-ChildItem -Path $WorkspaceDir -Directory | Where-Object { Test-Path "$($_.FullName)\.git" }
foreach ($project in $projects) {
    Write-Host "  Indexando: $($project.Name)..." -ForegroundColor Gray
    Push-Location $CodebaseRagDir
    if ($Runtime -eq "bun") {
        bun run src/cli.ts index $project.FullName
    } else {
        npx ts-node src/cli.ts index $project.FullName
    }
    Pop-Location
}

# 5. Configurar MCP para IntelliJ
Write-Host "Configurando integração MCP para IntelliJ Copilot..."
$IntelliJMcpDir = "$HOME\.config\github-copilot\intellij"
if (!(Test-Path $IntelliJMcpDir)) {
    New-Item -ItemType Directory -Path $IntelliJMcpDir -Force | Out-Null
}

$McpJsonPath = "$IntelliJMcpDir\mcp.json"

if ($Runtime -eq "bun") {
    $McpConfig = @{
        mcpServers = @{
            "local-code-rag" = @{
                command = "bun"
                args = @("run", "$CodebaseRagDir\src\server.ts")
                env = @{
                    CODEBASE_RAG_DATA = "$CodebaseRagDir\data"
                }
            }
        }
    }
} else {
    $McpConfig = @{
        mcpServers = @{
            "local-code-rag" = @{
                command = "npx"
                args = @("ts-node", "$CodebaseRagDir\src\server.ts")
                env = @{
                    CODEBASE_RAG_DATA = "$CodebaseRagDir\data"
                }
            }
        }
    }
}

$McpConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $McpJsonPath -Encoding UTF8
Write-Host "Arquivo mcp.json criado em $McpJsonPath" -ForegroundColor Green

Write-Host ""
Write-Host "Setup alternativo concluído!" -ForegroundColor Green
Write-Host "Vantagens desta abordagem:" -ForegroundColor Cyan
Write-Host "  - Não requer Ollama (embeddings via ONNX local, ~22MB)"
Write-Host "  - Busca híbrida (keyword + semântica)"
Write-Host "  - SQLite como armazenamento (zero dependências externas)"
Write-Host ""
Write-Host "Reinicie seu IntelliJ IDEA para carregar o servidor MCP." -ForegroundColor Yellow
