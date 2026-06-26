<#
.SYNOPSIS
    Instala e configura o Arize Phoenix para observabilidade de agentes MCP.

.DESCRIPTION
    Este script instala o Arize Phoenix (open-source) localmente via pip,
    configura variáveis de ambiente para modo offline/air-gapped, e opcionalmente
    inicia o servidor Phoenix para visualização de traces dos agentes.

    O Phoenix recebe traces via OpenTelemetry (OTLP) do mcp-proxy-logger.py,
    permitindo visualizar o fluxo de decisões dos agentes GitHub Copilot.

    Requisitos:
    - Python 3.9+ (já instalado via setup-codebase-memory.ps1 ou setup-vector-search.ps1)
    - ~200MB de espaço em disco
    - Sem necessidade de Docker ou privilégios de administrador

.PARAMETER Port
    Porta HTTP para o servidor Phoenix (UI + OTEL collector).
    Padrão: 6006

.PARAMETER GrpcPort
    Porta gRPC para o collector OTLP.
    Padrão: 4317

.PARAMETER WorkingDir
    Diretório para armazenamento de dados (SQLite, exports).
    Padrão: $HOME\.phoenix

.PARAMETER ProjectName
    Nome do projeto padrão no Phoenix.
    Padrão: copilot-agent-traces

.PARAMETER AirGapped
    Desabilita carregamento de recursos externos (Google Fonts, analytics).
    Recomendado para ambientes corporativos.

.PARAMETER Start
    Inicia o servidor Phoenix após a instalação.

.PARAMETER Stop
    Para o servidor Phoenix se estiver rodando.

.PARAMETER Status
    Verifica se o servidor Phoenix está rodando.

.PARAMETER Upgrade
    Atualiza o Phoenix para a versão mais recente.

.EXAMPLE
    .\scripts\setup-phoenix.ps1
    # Instala o Phoenix e dependências

.EXAMPLE
    .\scripts\setup-phoenix.ps1 -Start
    # Instala e inicia o servidor Phoenix

.EXAMPLE
    .\scripts\setup-phoenix.ps1 -Start -AirGapped -Port 9090
    # Inicia em modo air-gapped na porta 9090

.EXAMPLE
    .\scripts\setup-phoenix.ps1 -Status
    # Verifica se o Phoenix está rodando

.EXAMPLE
    .\scripts\setup-phoenix.ps1 -Stop
    # Para o servidor Phoenix
#>

[CmdletBinding()]
param(
    [int]$Port = 6006,
    [int]$GrpcPort = 4317,
    [string]$WorkingDir = "$env:USERPROFILE\.phoenix",
    [string]$ProjectName = "copilot-agent-traces",
    [switch]$AirGapped,
    [switch]$Start,
    [switch]$Stop,
    [switch]$Status,
    [switch]$Upgrade
)

# ─────────────────────────────────────────────────────────────────────────────
# Configuração
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$PhoenixPidFile = Join-Path $WorkingDir "phoenix.pid"
$PhoenixLogFile = Join-Path $WorkingDir "phoenix.log"

# ─────────────────────────────────────────────────────────────────────────────
# Funções Auxiliares
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n[Phoenix] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[ERRO] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Test-PythonAvailable {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    }
    if (-not $pythonCmd) {
        Write-Fail "Python não encontrado. Instale Python 3.9+ antes de continuar."
        exit 1
    }
    return $pythonCmd.Source
}

function Get-PhoenixProcess {
    Get-Process -Name "phoenix" -ErrorAction SilentlyContinue
    if (-not $?) {
        # Tenta encontrar pelo PID file
        if (Test-Path $PhoenixPidFile) {
            $pid = Get-Content $PhoenixPidFile -Raw
            Get-Process -Id $pid -ErrorAction SilentlyContinue
        }
    }
}

function Test-PortInUse {
    param([int]$PortNumber)
    $connection = Get-NetTCPConnection -LocalPort $PortNumber -ErrorAction SilentlyContinue
    return ($null -ne $connection)
}

# ─────────────────────────────────────────────────────────────────────────────
# Ação: Status
# ─────────────────────────────────────────────────────────────────────────────

if ($Status) {
    Write-Step "Verificando status do Phoenix..."

    $portInUse = Test-PortInUse -PortNumber $Port
    if ($portInUse) {
        Write-Success "Phoenix está rodando em http://localhost:$Port"
        Write-Host "  OTEL HTTP: http://localhost:$Port/v1/traces"
        Write-Host "  OTEL gRPC: localhost:$GrpcPort"
        Write-Host "  Working Dir: $WorkingDir"
    } else {
        Write-Warn "Phoenix NÃO está rodando na porta $Port"
    }

    # Verificar instalação
    $python = Test-PythonAvailable
    $installed = & $python -c "import phoenix; print(phoenix.__version__)" 2>$null
    if ($installed) {
        Write-Success "Phoenix instalado: v$installed"
    } else {
        Write-Warn "Phoenix não está instalado"
    }
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Ação: Stop
# ─────────────────────────────────────────────────────────────────────────────

if ($Stop) {
    Write-Step "Parando o servidor Phoenix..."

    if (Test-Path $PhoenixPidFile) {
        $pid = Get-Content $PhoenixPidFile -Raw
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $pid -Force
            Remove-Item $PhoenixPidFile -Force
            Write-Success "Phoenix parado (PID: $pid)"
        } else {
            Remove-Item $PhoenixPidFile -Force
            Write-Warn "PID $pid não encontrado (já estava parado)"
        }
    } else {
        # Tenta matar por porta
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($connections) {
            $ownerPid = $connections[0].OwningProcess
            Stop-Process -Id $ownerPid -Force
            Write-Success "Phoenix parado (PID: $ownerPid, porta $Port)"
        } else {
            Write-Warn "Nenhum processo Phoenix encontrado"
        }
    }
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Instalação
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Arize Phoenix — Agent Observability Setup             ║" -ForegroundColor Cyan
Write-Host "║       Tracing de decisões para agentes MCP/Copilot          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar Python
Write-Step "Verificando Python..."
$python = Test-PythonAvailable
$pyVersion = & $python --version 2>&1
Write-Success "Python encontrado: $pyVersion"

# 2. Criar diretório de trabalho
Write-Step "Criando diretório de trabalho..."
if (-not (Test-Path $WorkingDir)) {
    New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
}
Write-Success "Working dir: $WorkingDir"

# 3. Instalar/Atualizar Phoenix
Write-Step "Instalando Arize Phoenix..."

$pipArgs = @("install")
if ($Upgrade) {
    $pipArgs += "--upgrade"
}
$pipArgs += @(
    "arize-phoenix",
    "arize-phoenix-otel>=0.16.0",
    "opentelemetry-api",
    "opentelemetry-sdk",
    "opentelemetry-exporter-otlp-proto-http"
)

& $python -m pip $pipArgs --quiet --disable-pip-version-check 2>&1 | Out-Null

# Verificar instalação
$phoenixVersion = & $python -c "import phoenix; print(phoenix.__version__)" 2>$null
if (-not $phoenixVersion) {
    Write-Fail "Falha na instalação do Phoenix"
    exit 1
}
Write-Success "Phoenix v$phoenixVersion instalado"

# 4. Configurar variáveis de ambiente (user-level, persiste entre sessões)
Write-Step "Configurando variáveis de ambiente..."

$envVars = @{
    "PHOENIX_PORT"                    = $Port.ToString()
    "PHOENIX_GRPC_PORT"               = $GrpcPort.ToString()
    "PHOENIX_WORKING_DIR"             = $WorkingDir
    "PHOENIX_COLLECTOR_ENDPOINT"      = "http://localhost:$Port"
    "PHOENIX_PROJECT_NAME"            = $ProjectName
    "PHOENIX_TELEMETRY_ENABLED"       = "false"
}

if ($AirGapped) {
    $envVars["PHOENIX_ALLOW_EXTERNAL_RESOURCES"] = "false"
    $envVars["PHOENIX_ALLOWED_PROVIDERS"] = "OLLAMA"
}

foreach ($key in $envVars.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $envVars[$key], "User")
    $env:PSItem = $envVars[$key]  # Aplica na sessão atual também
    Set-Item -Path "Env:\$key" -Value $envVars[$key]
}

Write-Success "Variáveis de ambiente configuradas (user-level)"
Write-Host ""
Write-Host "  Configuração aplicada:" -ForegroundColor DarkGray
foreach ($key in $envVars.Keys | Sort-Object) {
    Write-Host "    $key = $($envVars[$key])" -ForegroundColor DarkGray
}

# 5. Criar script de inicialização rápida
Write-Step "Criando script de inicialização rápida..."

$startScript = @"
@echo off
REM Inicia o Arize Phoenix (Agent Observability)
set PHOENIX_PORT=$Port
set PHOENIX_GRPC_PORT=$GrpcPort
set PHOENIX_WORKING_DIR=$WorkingDir
set PHOENIX_COLLECTOR_ENDPOINT=http://localhost:$Port
set PHOENIX_PROJECT_NAME=$ProjectName
set PHOENIX_TELEMETRY_ENABLED=false
$(if ($AirGapped) { "set PHOENIX_ALLOW_EXTERNAL_RESOURCES=false`nset PHOENIX_ALLOWED_PROVIDERS=OLLAMA" })
echo.
echo [Phoenix] Iniciando servidor em http://localhost:$Port
echo [Phoenix] OTEL endpoint: http://localhost:$Port/v1/traces
echo [Phoenix] gRPC endpoint: localhost:$GrpcPort
echo [Phoenix] Pressione Ctrl+C para parar
echo.
phoenix serve
"@

$startScriptPath = Join-Path $WorkingDir "start-phoenix.bat"
Set-Content -Path $startScriptPath -Value $startScript -Encoding UTF8
Write-Success "Script criado: $startScriptPath"

# 6. Iniciar servidor (se solicitado)
if ($Start) {
    Write-Step "Iniciando servidor Phoenix..."

    # Verificar se porta já está em uso
    if (Test-PortInUse -PortNumber $Port) {
        Write-Warn "Porta $Port já está em uso. Phoenix pode já estar rodando."
        Write-Host "  Acesse: http://localhost:$Port"
        exit 0
    }

    # Iniciar em background
    $phoenixProcess = Start-Process -FilePath $python -ArgumentList "-m", "phoenix.server.main", "serve" `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $PhoenixLogFile `
        -RedirectStandardError (Join-Path $WorkingDir "phoenix-error.log")

    # Salvar PID
    $phoenixProcess.Id | Set-Content -Path $PhoenixPidFile

    # Aguardar inicialização
    Write-Host "  Aguardando inicialização..." -NoNewline
    $maxWait = 15
    $waited = 0
    while (-not (Test-PortInUse -PortNumber $Port) -and $waited -lt $maxWait) {
        Start-Sleep -Seconds 1
        $waited++
        Write-Host "." -NoNewline
    }
    Write-Host ""

    if (Test-PortInUse -PortNumber $Port) {
        Write-Success "Phoenix iniciado com sucesso!"
    } else {
        Write-Fail "Phoenix não respondeu em ${maxWait}s. Verifique: $PhoenixLogFile"
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    Setup Concluído                           ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Phoenix v$phoenixVersion" -ForegroundColor White
Write-Host ""
Write-Host "  Endpoints:" -ForegroundColor White
Write-Host "    UI:        http://localhost:$Port" -ForegroundColor Cyan
Write-Host "    OTEL HTTP: http://localhost:$Port/v1/traces" -ForegroundColor Cyan
Write-Host "    OTEL gRPC: localhost:$GrpcPort" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Comandos:" -ForegroundColor White
Write-Host "    Iniciar:   .\scripts\setup-phoenix.ps1 -Start" -ForegroundColor DarkGray
Write-Host "    Parar:     .\scripts\setup-phoenix.ps1 -Stop" -ForegroundColor DarkGray
Write-Host "    Status:    .\scripts\setup-phoenix.ps1 -Status" -ForegroundColor DarkGray
Write-Host "    Atualizar: .\scripts\setup-phoenix.ps1 -Upgrade" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Início rápido (sem PowerShell):" -ForegroundColor White
Write-Host "    $startScriptPath" -ForegroundColor DarkGray
Write-Host ""

if (-not $Start) {
    Write-Host "  Para iniciar o Phoenix agora:" -ForegroundColor Yellow
    Write-Host "    .\scripts\setup-phoenix.ps1 -Start" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ou manualmente:" -ForegroundColor Yellow
    Write-Host "    phoenix serve" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Próximo passo:" -ForegroundColor White
Write-Host "    Habilitar monitoramento MCP para enviar traces ao Phoenix:" -ForegroundColor DarkGray
Write-Host "    .\scripts\toggle-monitoring.ps1 -Enable -Phoenix" -ForegroundColor DarkGray
Write-Host ""
