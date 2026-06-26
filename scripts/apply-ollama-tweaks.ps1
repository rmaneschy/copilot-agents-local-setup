<#
.SYNOPSIS
Aplica configurações otimizadas do Ollama com base no perfil de hardware detectado.

.DESCRIPTION
Script dedicado e independente para detectar o hardware da máquina e aplicar (ou trocar)
as variáveis de ambiente do Ollama sem executar o setup completo.

Casos de uso:
- Reaplicar configurações após atualização do Ollama
- Trocar de perfil rapidamente (ex: ao conectar eGPU ou dock station)
- Verificar se as configurações ativas estão corretas
- Executar como rotina diária ou pós-boot

O script detecta GPU (NVIDIA via nvidia-smi, ou WMI), RAM e CPU, determina o perfil
adequado (LIGHT, MEDIUM, POWER), aplica as variáveis de ambiente do Ollama no escopo
do usuário e reinicia o serviço para que as mudanças entrem em vigor imediatamente.

.PARAMETER Profile
Força um perfil de hardware específico: 'light', 'medium' ou 'power'.
Se não informado, o script detecta automaticamente com base no hardware.

.PARAMETER DryRun
Exibe as configurações que seriam aplicadas sem efetivamente alterar nada.
Útil para validar antes de aplicar.

.PARAMETER Reset
Remove todas as variáveis de ambiente OLLAMA_* do escopo do usuário,
retornando o Ollama aos valores padrão de fábrica.

.PARAMETER Verify
Apenas exibe as configurações atualmente ativas sem alterar nada.

.EXAMPLE
.\scripts\apply-ollama-tweaks.ps1
# Detecta hardware e aplica perfil automaticamente

.EXAMPLE
.\scripts\apply-ollama-tweaks.ps1 -Profile power
# Força o perfil POWER independentemente do hardware

.EXAMPLE
.\scripts\apply-ollama-tweaks.ps1 -DryRun
# Mostra o que seria aplicado sem alterar nada

.EXAMPLE
.\scripts\apply-ollama-tweaks.ps1 -Verify
# Exibe as configurações atualmente ativas

.EXAMPLE
.\scripts\apply-ollama-tweaks.ps1 -Reset
# Remove todas as variáveis OLLAMA_* e restaura padrões
#>

param(
    [ValidateSet("light", "medium", "power", "")]
    [string]$Profile = "",
    [switch]$DryRun,
    [switch]$Reset,
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$ToolsDir = "$HOME\local-tools"

# ═══════════════════════════════════════════════════════════════════════════════
# Banner
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  Ollama Tweaks — Configuração de Performance               ║" -ForegroundColor Magenta
Write-Host "║  Detecção automática de hardware + perfis otimizados       ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Modo: Verify (apenas exibir configurações ativas)
# ═══════════════════════════════════════════════════════════════════════════════
if ($Verify) {
    Write-Host "  [MODO VERIFICAÇÃO] Configurações atualmente ativas:" -ForegroundColor Cyan
    Write-Host ""

    $ollamaVars = @(
        "OLLAMA_FLASH_ATTENTION",
        "OLLAMA_KV_CACHE_TYPE",
        "OLLAMA_CONTEXT_LENGTH",
        "OLLAMA_KEEP_ALIVE",
        "OLLAMA_NUM_PARALLEL",
        "OLLAMA_MAX_LOADED_MODELS",
        "OLLAMA_HOST",
        "OLLAMA_MODELS",
        "OLLAMA_GPU_OVERHEAD",
        "OLLAMA_SCHED_SPREAD",
        "OLLAMA_MAX_QUEUE",
        "OLLAMA_DEBUG"
    )

    Write-Host "  ┌────────────────────────────────┬────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │ Variável                       │ Valor                      │" -ForegroundColor DarkCyan
    Write-Host "  ├────────────────────────────────┼────────────────────────────┤" -ForegroundColor DarkCyan

    foreach ($var in $ollamaVars) {
        $value = [System.Environment]::GetEnvironmentVariable($var, "User")
        if ($null -eq $value) { $value = "(não definido)" }
        $varPadded = $var.PadRight(30)
        $valPadded = $value.PadRight(26)
        $color = if ($value -eq "(não definido)") { "DarkGray" } else { "White" }
        Write-Host "  │ $varPadded │ $valPadded │" -ForegroundColor $color
    }

    Write-Host "  └────────────────────────────────┴────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""

    # Verificar se o Ollama está rodando
    $ollamaProc = Get-Process ollama* -ErrorAction SilentlyContinue
    if ($ollamaProc) {
        Write-Host "  Ollama: " -NoNewline -ForegroundColor White
        Write-Host "RODANDO (PID: $($ollamaProc.Id))" -ForegroundColor Green
    } else {
        Write-Host "  Ollama: " -NoNewline -ForegroundColor White
        Write-Host "PARADO" -ForegroundColor Yellow
    }

    # Verificar perfil salvo
    $ProfileFile = "$ToolsDir\hardware-profile.json"
    if (Test-Path $ProfileFile) {
        $savedProfile = Get-Content $ProfileFile -Raw | ConvertFrom-Json
        Write-Host "  Perfil salvo: " -NoNewline -ForegroundColor White
        Write-Host "$($savedProfile.profile.ToUpper()) (detectado em $($savedProfile.detected_at))" -ForegroundColor Cyan
    }

    Write-Host ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Modo: Reset (remover todas as variáveis OLLAMA_*)
# ═══════════════════════════════════════════════════════════════════════════════
if ($Reset) {
    Write-Host "  [MODO RESET] Removendo todas as variáveis OLLAMA_*..." -ForegroundColor Yellow
    Write-Host ""

    $ollamaVars = @(
        "OLLAMA_FLASH_ATTENTION",
        "OLLAMA_KV_CACHE_TYPE",
        "OLLAMA_CONTEXT_LENGTH",
        "OLLAMA_KEEP_ALIVE",
        "OLLAMA_NUM_PARALLEL",
        "OLLAMA_MAX_LOADED_MODELS",
        "OLLAMA_GPU_OVERHEAD",
        "OLLAMA_SCHED_SPREAD"
    )

    foreach ($var in $ollamaVars) {
        $current = [System.Environment]::GetEnvironmentVariable($var, "User")
        if ($null -ne $current) {
            [System.Environment]::SetEnvironmentVariable($var, $null, "User")
            Write-Host "    REMOVIDO: $var (era: $current)" -ForegroundColor DarkGray
        }
    }

    # Remover perfil salvo
    $ProfileFile = "$ToolsDir\hardware-profile.json"
    if (Test-Path $ProfileFile) {
        Remove-Item $ProfileFile -Force
        Write-Host "    REMOVIDO: hardware-profile.json" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  OK: Todas as variáveis removidas. Ollama usará valores padrão." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Padrões de fábrica do Ollama:" -ForegroundColor White
    Write-Host "    Flash Attention:   Desabilitado" -ForegroundColor DarkGray
    Write-Host "    KV Cache:          f16 (sem quantização)" -ForegroundColor DarkGray
    Write-Host "    Context Length:    4096 tokens" -ForegroundColor DarkGray
    Write-Host "    Keep Alive:        5 minutos" -ForegroundColor DarkGray
    Write-Host "    Num Parallel:      1" -ForegroundColor DarkGray
    Write-Host "    Max Loaded Models: 3" -ForegroundColor DarkGray
    Write-Host ""

    # Reiniciar Ollama
    $ollamaProc = Get-Process ollama* -ErrorAction SilentlyContinue
    if ($ollamaProc) {
        Write-Host "  Reiniciando Ollama com padrões de fábrica..." -ForegroundColor Cyan
        $ollamaProc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 5
        Write-Host "  OK: Ollama reiniciado." -ForegroundColor Green
    }

    Write-Host ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Detecção de Hardware
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "  [1/4] Detectando hardware..." -ForegroundColor White

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
        if ($gpuInfo.AdapterRAM -eq [uint32]::MaxValue -or $gpuInfo.AdapterRAM -eq 0) {
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

    # Fallback: nvidia-smi
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
    Write-Host "    AVISO: Não foi possível detectar GPU." -ForegroundColor Yellow
}

# --- Detectar RAM ---
$RamGB = 0
try {
    $ramInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $RamGB = [math]::Round($ramInfo.TotalPhysicalMemory / 1GB, 0)
} catch {
    $RamGB = 8
}

# --- Detectar CPU ---
$CpuCores = 0
$CpuName = "Não detectado"
try {
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $CpuCores = $cpuInfo.NumberOfLogicalProcessors
    $CpuName = $cpuInfo.Name.Trim()
} catch {
    $CpuCores = 4
}

# --- Exibir hardware ---
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

# ═══════════════════════════════════════════════════════════════════════════════
# Determinar Perfil
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "  [2/4] Determinando perfil..." -ForegroundColor White

if ($Profile -eq "") {
    if ($VramGB -ge 12 -and $RamGB -ge 32) {
        $Profile = "power"
    } elseif ($VramGB -ge 6 -and $RamGB -ge 16) {
        $Profile = "medium"
    } else {
        $Profile = "light"
    }
    Write-Host "    Perfil detectado automaticamente: " -NoNewline -ForegroundColor White
} else {
    Write-Host "    Perfil forçado pelo usuário: " -NoNewline -ForegroundColor White
}

switch ($Profile) {
    "light"  { Write-Host "LIGHT (Econômico)" -ForegroundColor Yellow }
    "medium" { Write-Host "MEDIUM (Equilibrado)" -ForegroundColor Cyan }
    "power"  { Write-Host "POWER (Máximo Desempenho)" -ForegroundColor Green }
}

# --- Definir configurações por perfil ---
$OllamaConfig = [ordered]@{}
$ProfileDetails = @{}

switch ($Profile) {
    "light" {
        $OllamaConfig = [ordered]@{
            OLLAMA_FLASH_ATTENTION   = "1"
            OLLAMA_KV_CACHE_TYPE     = "q4_0"
            OLLAMA_CONTEXT_LENGTH    = "8192"
            OLLAMA_KEEP_ALIVE        = "5m"
            OLLAMA_NUM_PARALLEL      = "1"
            OLLAMA_MAX_LOADED_MODELS = "1"
        }
        $ProfileDetails = @{
            RecommendedModel = "qwen2.5-coder:3b"
            ContextDesc      = "8K tokens"
            KvDesc           = "q4_0 (economia máxima, -66% VRAM)"
            VramEstimate     = "~2-3 GB"
            AgentCapability  = "1-2 arquivos simultâneos, tarefas pontuais"
        }
    }
    "medium" {
        $OllamaConfig = [ordered]@{
            OLLAMA_FLASH_ATTENTION   = "1"
            OLLAMA_KV_CACHE_TYPE     = "q8_0"
            OLLAMA_CONTEXT_LENGTH    = "32768"
            OLLAMA_KEEP_ALIVE        = "-1"
            OLLAMA_NUM_PARALLEL      = "2"
            OLLAMA_MAX_LOADED_MODELS = "1"
        }
        $ProfileDetails = @{
            RecommendedModel = "qwen2.5-coder:7b"
            ContextDesc      = "32K tokens"
            KvDesc           = "q8_0 (equilíbrio, -50% VRAM, qualidade imperceptível)"
            VramEstimate     = "~6-8 GB"
            AgentCapability  = "5-10 arquivos simultâneos, fluxo SDD completo"
        }
    }
    "power" {
        $OllamaConfig = [ordered]@{
            OLLAMA_FLASH_ATTENTION   = "1"
            OLLAMA_KV_CACHE_TYPE     = "q8_0"
            OLLAMA_CONTEXT_LENGTH    = "65536"
            OLLAMA_KEEP_ALIVE        = "-1"
            OLLAMA_NUM_PARALLEL      = "4"
            OLLAMA_MAX_LOADED_MODELS = "2"
        }
        $ProfileDetails = @{
            RecommendedModel = "qwen2.5-coder:14b"
            ContextDesc      = "64K tokens (ideal para agentes autônomos)"
            KvDesc           = "q8_0 (qualidade máxima prática)"
            VramEstimate     = "~12-16 GB"
            AgentCapability  = "20-40 arquivos, módulo inteiro, 4 MCP tools paralelas"
        }
    }
}

Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │ CONFIGURAÇÕES DO PERFIL $($Profile.ToUpper().PadRight(34))│" -ForegroundColor DarkCyan
Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
Write-Host "  │ Context Window:  $($ProfileDetails.ContextDesc.PadRight(40))│" -ForegroundColor DarkCyan
Write-Host "  │ KV Cache:        $($ProfileDetails.KvDesc.PadRight(40))│" -ForegroundColor DarkCyan
Write-Host "  │ VRAM Estimada:   $($ProfileDetails.VramEstimate.PadRight(40))│" -ForegroundColor DarkCyan
Write-Host "  │ Modelo Sugerido: $($ProfileDetails.RecommendedModel.PadRight(40))│" -ForegroundColor DarkCyan
Write-Host "  │ Capacidade:      $($ProfileDetails.AgentCapability.PadRight(40))│" -ForegroundColor DarkCyan
Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Aplicar Configurações (ou DryRun)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "  [3/4] Aplicando variáveis de ambiente..." -ForegroundColor White

if ($DryRun) {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │ MODO DRY-RUN: Nenhuma alteração será feita.                │" -ForegroundColor Yellow
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Variáveis que SERIAM aplicadas:" -ForegroundColor White
    Write-Host ""

    foreach ($key in $OllamaConfig.Keys) {
        $currentValue = [System.Environment]::GetEnvironmentVariable($key, "User")
        $newValue = $OllamaConfig[$key]
        if ($currentValue -ne $newValue) {
            if ($null -eq $currentValue) { $currentValue = "(não definido)" }
            Write-Host "    MUDARIA: $key" -ForegroundColor Cyan
            Write-Host "             Atual: $currentValue" -ForegroundColor DarkGray
            Write-Host "             Novo:  $newValue" -ForegroundColor White
        } else {
            Write-Host "    SEM MUDANÇA: $key = $newValue" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  Para aplicar de verdade, execute sem -DryRun:" -ForegroundColor Yellow
    Write-Host "    .\scripts\apply-ollama-tweaks.ps1 -Profile $Profile" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# --- Aplicar variáveis ---
$envChanged = $false
$changedVars = @()

foreach ($key in $OllamaConfig.Keys) {
    $currentValue = [System.Environment]::GetEnvironmentVariable($key, "User")
    $newValue = $OllamaConfig[$key]

    if ($currentValue -ne $newValue) {
        [System.Environment]::SetEnvironmentVariable($key, $newValue, "User")
        # Também aplicar na sessão atual para efeito imediato
        [System.Environment]::SetEnvironmentVariable($key, $newValue, "Process")
        $envChanged = $true
        $changedVars += $key
        $oldDisplay = if ($null -eq $currentValue) { "(não definido)" } else { $currentValue }
        Write-Host "    ATUALIZADO: $key = $newValue (era: $oldDisplay)" -ForegroundColor White
    } else {
        Write-Host "    OK:         $key = $newValue (sem mudança)" -ForegroundColor DarkGray
    }
}

Write-Host ""

if ($envChanged) {
    Write-Host "  Variáveis alteradas: $($changedVars.Count)" -ForegroundColor Cyan
    Write-Host "    $($changedVars -join ', ')" -ForegroundColor DarkGray
} else {
    Write-Host "  Todas as configurações já estavam corretas. Nenhuma mudança necessária." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# Reiniciar Ollama (se houve mudanças)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [4/4] Verificando Ollama..." -ForegroundColor White

if (!(Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "  AVISO: Ollama não encontrado no PATH." -ForegroundColor Yellow
    Write-Host "  As variáveis foram salvas e serão aplicadas quando o Ollama for instalado." -ForegroundColor Yellow
    Write-Host ""
} else {
    $ollamaProc = Get-Process ollama* -ErrorAction SilentlyContinue

    if ($envChanged -and $ollamaProc) {
        Write-Host "    Reiniciando Ollama para aplicar novas configurações..." -ForegroundColor Cyan
        $ollamaProc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 5

        # Verificar se reiniciou corretamente
        try {
            $null = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 10 -ErrorAction Stop
            Write-Host "    OK: Ollama reiniciado e respondendo." -ForegroundColor Green
        } catch {
            Write-Host "    AVISO: Ollama reiniciado mas não respondeu em 10s. Aguarde mais um momento." -ForegroundColor Yellow
        }
    } elseif (-not $ollamaProc) {
        Write-Host "    Ollama não está rodando. Iniciando..." -ForegroundColor Cyan
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 5

        try {
            $null = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 10 -ErrorAction Stop
            Write-Host "    OK: Ollama iniciado e respondendo." -ForegroundColor Green
        } catch {
            Write-Host "    AVISO: Ollama iniciado mas não respondeu em 10s." -ForegroundColor Yellow
        }
    } else {
        Write-Host "    OK: Ollama rodando. Nenhuma mudança, reinício não necessário." -ForegroundColor Green
    }

    # Verificar modelos carregados
    Write-Host ""
    Write-Host "  Modelos atualmente carregados:" -ForegroundColor White
    $psOutput = ollama ps 2>&1
    if ($psOutput -match "NAME") {
        Write-Host "    $psOutput" -ForegroundColor DarkGray
    } else {
        Write-Host "    (nenhum modelo carregado no momento)" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Salvar perfil para uso por outros scripts
# ═══════════════════════════════════════════════════════════════════════════════
if (!(Test-Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir | Out-Null }

$ProfileFile = "$ToolsDir\hardware-profile.json"
$profileData = @{
    profile       = $Profile
    detected_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    applied_by    = "apply-ollama-tweaks.ps1"
    hardware      = @{
        gpu_name  = $GpuName
        vram_gb   = $VramGB
        ram_gb    = $RamGB
        cpu_name  = $CpuName
        cpu_cores = $CpuCores
    }
    ollama_config = $OllamaConfig
    recommended_model = $ProfileDetails.RecommendedModel
    context_desc  = $ProfileDetails.ContextDesc
    agent_capability = $ProfileDetails.AgentCapability
} | ConvertTo-Json -Depth 3

$profileData | Out-File -FilePath $ProfileFile -Encoding UTF8

# ═══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  TWEAKS APLICADOS COM SUCESSO                               ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Perfil:          $($Profile.ToUpper().PadRight(38))║" -ForegroundColor Green
Write-Host "║  Context Window:  $($ProfileDetails.ContextDesc.PadRight(38))║" -ForegroundColor Green
Write-Host "║  KV Cache:        $($OllamaConfig['OLLAMA_KV_CACHE_TYPE'].PadRight(38))║" -ForegroundColor Green
Write-Host ("║  Flash Attention: Habilitado" + "".PadRight(29) + "║") -ForegroundColor Green
$parallelStr = "$($OllamaConfig['OLLAMA_NUM_PARALLEL']) requisições simultâneas"
Write-Host ("║  Paralelismo:     " + $parallelStr.PadRight(38) + "║") -ForegroundColor Green
$keepAliveStr = if ($OllamaConfig['OLLAMA_KEEP_ALIVE'] -eq '-1') { "Permanente (modelo sempre carregado)" } else { $OllamaConfig['OLLAMA_KEEP_ALIVE'] }
Write-Host ("║  Keep Alive:      " + $keepAliveStr.PadRight(38) + "║") -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Modelo sugerido: ollama pull $($ProfileDetails.RecommendedModel.PadRight(26))║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Perfil salvo em: $ProfileFile" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Comandos úteis:" -ForegroundColor White
Write-Host "    .\scripts\apply-ollama-tweaks.ps1 -Verify     # Ver configurações ativas" -ForegroundColor DarkGray
Write-Host "    .\scripts\apply-ollama-tweaks.ps1 -Profile X  # Forçar outro perfil" -ForegroundColor DarkGray
Write-Host "    .\scripts\apply-ollama-tweaks.ps1 -Reset      # Restaurar padrões" -ForegroundColor DarkGray
Write-Host "    .\scripts\apply-ollama-tweaks.ps1 -DryRun     # Simular sem aplicar" -ForegroundColor DarkGray
Write-Host ""
