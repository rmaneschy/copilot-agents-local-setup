<#
.SYNOPSIS
Script de configuração do RAG local para código-fonte no Windows (Sem Admin, Sem Docker).

.DESCRIPTION
Este script realiza o download e configuração do Ollama, instala o Python (se necessário),
configura o ambiente virtual e instala o servidor MCP mcp-vector-search.

Inclui detecção automática de hardware (VRAM, RAM, CPU) para aplicar o perfil de
configuração ideal do Ollama para a máquina do engenheiro.

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

.PARAMETER Profile
Força um perfil de hardware específico: 'light', 'medium' ou 'power'.
Se não informado, o script detecta automaticamente.

.PARAMETER SkipOllamaTweaks
Pula a configuração de variáveis de ambiente do Ollama.
#>

param(
    [switch]$SkipModelDownload,
    [string]$ModelPath = "",
    [switch]$UseOllamaPull,
    [ValidateSet("light", "medium", "power", "")]
    [string]$Profile = "",
    [switch]$SkipOllamaTweaks
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
# 1. Detectar Hardware e Determinar Perfil
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[1/6] Detectando hardware..." -ForegroundColor White

# --- Detectar VRAM ---
$VramGB = 0
$GpuName = "Não detectada"
try {
    $gpuInfo = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.AdapterRAM -gt 0 -and $_.Name -notmatch "Microsoft|Virtual|Remote" } |
        Sort-Object AdapterRAM -Descending |
        Select-Object -First 1

    if ($gpuInfo) {
        $GpuName = $gpuInfo.Name
        # Win32_VideoController.AdapterRAM é limitado a 4GB (uint32).
        # Para GPUs maiores, tentamos via nvidia-smi ou registry.
        if ($gpuInfo.AdapterRAM -eq [uint32]::MaxValue -or $gpuInfo.AdapterRAM -eq 0) {
            # Tentar nvidia-smi para GPUs NVIDIA
            if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                $nvidiaMem = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null |
                    Select-Object -First 1
                if ($nvidiaMem) {
                    $VramGB = [math]::Round([int]$nvidiaMem / 1024, 1)
                }
            }
        } else {
            $VramGB = [math]::Round($gpuInfo.AdapterRAM / 1GB, 1)
        }
    }

    # Fallback: nvidia-smi se ainda não detectou
    if ($VramGB -eq 0 -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        $nvidiaMem = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null |
            Select-Object -First 1
        if ($nvidiaMem) {
            $VramGB = [math]::Round([int]$nvidiaMem / 1024, 1)
            $nvidiaName = nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
            if ($nvidiaName) { $GpuName = $nvidiaName.Trim() }
        }
    }
} catch {
    Write-Host "  AVISO: Não foi possível detectar GPU." -ForegroundColor Yellow
}

# --- Detectar RAM ---
$RamGB = 0
try {
    $ramInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $RamGB = [math]::Round($ramInfo.TotalPhysicalMemory / 1GB, 0)
} catch {
    $RamGB = 8 # Fallback conservador
}

# --- Detectar CPU ---
$CpuCores = 0
$CpuName = "Não detectado"
try {
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $CpuCores = $cpuInfo.NumberOfLogicalProcessors
    $CpuName = $cpuInfo.Name.Trim()
} catch {
    $CpuCores = 4 # Fallback conservador
}

# --- Exibir hardware detectado ---
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │ HARDWARE DETECTADO                                          │" -ForegroundColor DarkCyan
Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
Write-Host "  │ GPU:   $($GpuName.PadRight(50))│" -ForegroundColor DarkCyan
Write-Host "  │ VRAM:  $("$VramGB GB".PadRight(50))│" -ForegroundColor DarkCyan
Write-Host "  │ RAM:   $("$RamGB GB".PadRight(50))│" -ForegroundColor DarkCyan
Write-Host "  │ CPU:   $($CpuName.Substring(0, [Math]::Min($CpuName.Length, 50)).PadRight(50))│" -ForegroundColor DarkCyan
Write-Host "  │ Cores: $("$CpuCores logical cores".PadRight(50))│" -ForegroundColor DarkCyan
Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
Write-Host ""

# --- Determinar perfil ---
if ($Profile -eq "") {
    if ($VramGB -ge 12 -and $RamGB -ge 32) {
        $Profile = "power"
    } elseif ($VramGB -ge 6 -and $RamGB -ge 16) {
        $Profile = "medium"
    } else {
        $Profile = "light"
    }
    Write-Host "  Perfil detectado automaticamente: " -NoNewline -ForegroundColor White
} else {
    Write-Host "  Perfil forçado pelo usuário: " -NoNewline -ForegroundColor White
}

switch ($Profile) {
    "light"  { Write-Host "LIGHT (Econômico)" -ForegroundColor Yellow }
    "medium" { Write-Host "MEDIUM (Equilibrado)" -ForegroundColor Cyan }
    "power"  { Write-Host "POWER (Máximo Desempenho)" -ForegroundColor Green }
}

# --- Definir configurações por perfil ---
$OllamaConfig = @{}
switch ($Profile) {
    "light" {
        $OllamaConfig = @{
            OLLAMA_FLASH_ATTENTION  = "1"
            OLLAMA_KV_CACHE_TYPE   = "q4_0"
            OLLAMA_CONTEXT_LENGTH  = "8192"
            OLLAMA_KEEP_ALIVE      = "5m"
            OLLAMA_NUM_PARALLEL    = "1"
            OLLAMA_MAX_LOADED_MODELS = "1"
        }
        $RecommendedModel = "qwen2.5-coder:3b"
        $ContextDesc = "8K tokens"
        $KvDesc = "q4_0 (economia máxima, -66% VRAM)"
    }
    "medium" {
        $OllamaConfig = @{
            OLLAMA_FLASH_ATTENTION  = "1"
            OLLAMA_KV_CACHE_TYPE   = "q8_0"
            OLLAMA_CONTEXT_LENGTH  = "32768"
            OLLAMA_KEEP_ALIVE      = "-1"
            OLLAMA_NUM_PARALLEL    = "2"
            OLLAMA_MAX_LOADED_MODELS = "1"
        }
        $RecommendedModel = "qwen2.5-coder:7b"
        $ContextDesc = "32K tokens"
        $KvDesc = "q8_0 (equilíbrio, -50% VRAM)"
    }
    "power" {
        $OllamaConfig = @{
            OLLAMA_FLASH_ATTENTION  = "1"
            OLLAMA_KV_CACHE_TYPE   = "q8_0"
            OLLAMA_CONTEXT_LENGTH  = "65536"
            OLLAMA_KEEP_ALIVE      = "-1"
            OLLAMA_NUM_PARALLEL    = "4"
            OLLAMA_MAX_LOADED_MODELS = "2"
        }
        $RecommendedModel = "qwen2.5-coder:14b"
        $ContextDesc = "64K tokens (ideal para agentes)"
        $KvDesc = "q8_0 (qualidade máxima prática)"
    }
}

Write-Host ""
Write-Host "  Configurações do perfil:" -ForegroundColor White
Write-Host "    Context Window:  $ContextDesc" -ForegroundColor Gray
Write-Host "    KV Cache:        $KvDesc" -ForegroundColor Gray
Write-Host "    Modelo sugerido: $RecommendedModel" -ForegroundColor Gray
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# 2. Criar diretórios
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[2/6] Criando diretórios..." -ForegroundColor White
@($ToolsDir, $OllamaDir, $ModelsDir) | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null }
}
Write-Host "  OK: Diretórios criados em $ToolsDir" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 3. Verificar Ollama e Aplicar Tweaks
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[3/6] Verificando Ollama..." -ForegroundColor White
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

# --- Aplicar variáveis de ambiente do Ollama ---
if (-not $SkipOllamaTweaks) {
    Write-Host ""
    Write-Host "  Aplicando configurações de performance (perfil: $Profile)..." -ForegroundColor White

    $envChanged = $false
    foreach ($key in $OllamaConfig.Keys) {
        $currentValue = [System.Environment]::GetEnvironmentVariable($key, "User")
        $newValue = $OllamaConfig[$key]

        if ($currentValue -ne $newValue) {
            [System.Environment]::SetEnvironmentVariable($key, $newValue, "User")
            $envChanged = $true
            Write-Host "    SET $key = $newValue" -ForegroundColor DarkGray
        } else {
            Write-Host "    OK  $key = $newValue (já configurado)" -ForegroundColor DarkGray
        }
    }

    if ($envChanged) {
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "  │ IMPORTANTE: Variáveis de ambiente atualizadas.              │" -ForegroundColor Yellow
        Write-Host "  │ O Ollama precisa ser REINICIADO para aplicar as mudanças.   │" -ForegroundColor Yellow
        Write-Host "  │                                                             │" -ForegroundColor Yellow
        Write-Host "  │ Feche o Ollama no System Tray e abra novamente.             │" -ForegroundColor Yellow
        Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""

        # Tentar reiniciar o Ollama automaticamente
        $ollamaProc = Get-Process ollama* -ErrorAction SilentlyContinue
        if ($ollamaProc) {
            Write-Host "  Reiniciando Ollama para aplicar configurações..." -ForegroundColor Cyan
            $ollamaProc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 5
            Write-Host "  OK: Ollama reiniciado com novas configurações." -ForegroundColor Green
        }
    } else {
        Write-Host "  OK: Todas as configurações já estavam aplicadas." -ForegroundColor Green
    }
} else {
    Write-Host "  SKIP: Tweaks do Ollama ignorados (flag -SkipOllamaTweaks)." -ForegroundColor Yellow
}

# Iniciar Ollama em background se não estiver rodando
$OllamaProcess = Get-Process ollama* -ErrorAction SilentlyContinue
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

# Verificar se as configurações estão ativas
Write-Host ""
Write-Host "  Verificando configurações ativas..." -ForegroundColor White
$activeKv = [System.Environment]::GetEnvironmentVariable("OLLAMA_KV_CACHE_TYPE", "User")
$activeFa = [System.Environment]::GetEnvironmentVariable("OLLAMA_FLASH_ATTENTION", "User")
$activeCtx = [System.Environment]::GetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", "User")
Write-Host "    Flash Attention: $(if ($activeFa -eq '1') { 'ATIVO' } else { 'INATIVO' })" -ForegroundColor $(if ($activeFa -eq '1') { 'Green' } else { 'Yellow' })
Write-Host "    KV Cache Type:   $activeKv" -ForegroundColor $(if ($activeKv -eq 'q8_0' -or $activeKv -eq 'q4_0') { 'Green' } else { 'Yellow' })
Write-Host "    Context Length:  $activeCtx tokens" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# 4. Baixar e importar modelo de embedding
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[4/6] Configurando modelo de embedding ($ModelName)..." -ForegroundColor White

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
# 5. Configurar Python e mcp-vector-search
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[5/6] Configurando Python e mcp-vector-search..." -ForegroundColor White

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
# 6. Configurar integração com IntelliJ (mcp.json)
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[6/6] Configurando integração MCP para IntelliJ Copilot..." -ForegroundColor White

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
# Salvar perfil detectado para uso por outros scripts
# ═══════════════════════════════════════════════════════════════════════════
$ProfileFile = "$ToolsDir\hardware-profile.json"
$profileData = @{
    profile = $Profile
    detected_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    hardware = @{
        gpu_name = $GpuName
        vram_gb = $VramGB
        ram_gb = $RamGB
        cpu_name = $CpuName
        cpu_cores = $CpuCores
    }
    ollama_config = $OllamaConfig
    recommended_model = $RecommendedModel
} | ConvertTo-Json -Depth 3

$profileData | Out-File -FilePath $ProfileFile -Encoding UTF8
Write-Host ""
Write-Host "  Perfil salvo em: $ProfileFile" -ForegroundColor DarkGray

# ═══════════════════════════════════════════════════════════════════════════
# Resumo final
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  CONFIGURAÇÃO CONCLUÍDA COM SUCESSO                         ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Perfil aplicado: $($Profile.ToUpper().PadRight(39))║" -ForegroundColor Green
Write-Host "║  Modelo sugerido: $($RecommendedModel.PadRight(39))║" -ForegroundColor Green
Write-Host "║  Context Window:  $($ContextDesc.PadRight(39))║" -ForegroundColor Green
Write-Host "║  KV Cache:        $($KvDesc.PadRight(39))║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Próximos passos:                                           ║" -ForegroundColor Green
Write-Host "║  1. Baixar modelo de código (se ainda não tem):             ║" -ForegroundColor Green
Write-Host "║     ollama pull $($RecommendedModel.PadRight(43))║" -ForegroundColor Green
Write-Host "║  2. Indexar o workspace:                                    ║" -ForegroundColor Green
Write-Host "║     .\scripts\index-workspace.ps1                           ║" -ForegroundColor Green
Write-Host "║  3. Reiniciar o IntelliJ IDEA                               ║" -ForegroundColor Green
Write-Host "║  4. Verificar saúde do ambiente:                            ║" -ForegroundColor Green
Write-Host "║     .\scripts\health-check.ps1                              ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Dica: Para forçar outro perfil, use:" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup.ps1 -Profile medium" -ForegroundColor DarkGray
Write-Host "    .\scripts\setup.ps1 -Profile power" -ForegroundColor DarkGray
Write-Host ""
