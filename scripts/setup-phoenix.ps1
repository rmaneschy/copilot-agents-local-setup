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
    # Ordem de preferência: py -3.12 > py -3.13 > py -3 > python > python3
    # Prioriza 3.12 porque é a versão com melhor compatibilidade de wheels
    $candidates = @()

    # Tentar py launcher (Windows) com versões específicas
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        foreach ($ver in @("3.12", "3.13", "3.11", "3.10", "3.14")) {
            try {
                $testOutput = & py "-$ver" --version 2>$null
                if ($LASTEXITCODE -eq 0 -and $testOutput) {
                    $candidates += @{ Command = "py"; Args = "-$ver"; Version = $ver; Display = $testOutput }
                }
            } catch { }
        }
    }

    # Tentar python/python3 diretamente
    foreach ($cmd in @("python", "python3")) {
        $pythonCmd = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            $candidates += @{ Command = $pythonCmd.Source; Args = $null; Version = $null; Display = $null }
        }
    }

    if ($candidates.Count -eq 0) {
        Write-Fail "Python nao encontrado. Instale Python 3.10+ antes de continuar."
        exit 1
    }

    # Selecionar o melhor candidato (primeiro da lista de prioridade)
    $selected = $candidates[0]
    if ($selected.Args) {
        # Retornar como array para uso posterior: py -3.12
        $script:PythonArgs = $selected.Args
        return $selected.Command
    } else {
        $script:PythonArgs = $null
        return $selected.Command
    }
}

function Invoke-Python {
    param([string[]]$Arguments)
    if ($script:PythonArgs) {
        $allArgs = @($script:PythonArgs) + $Arguments
        & $script:PythonExe @allArgs
    } else {
        & $script:PythonExe @Arguments
    }
}

function Get-PythonVersion {
    $versionOutput = Invoke-Python @("--version")
    return $versionOutput
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
    $script:PythonExe = Test-PythonAvailable
    $installed = Invoke-Python @("-c", "import phoenix; print(phoenix.__version__)") 2>$null
    if ($installed) {
        Write-Success "Phoenix instalado: v$installed"
    } else {
        Write-Warn "Phoenix nao esta instalado"
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
$script:PythonExe = Test-PythonAvailable
$pyVersion = Get-PythonVersion
Write-Success "Python encontrado: $pyVersion"
if ($script:PythonArgs) {
    Write-Host "    Usando: $($script:PythonExe) $($script:PythonArgs)" -ForegroundColor DarkGray
}

# 2. Criar diretório de trabalho
Write-Step "Criando diretório de trabalho..."
if (-not (Test-Path $WorkingDir)) {
    New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
}
Write-Success "Working dir: $WorkingDir"

# 3. Instalar/Atualizar Phoenix
Write-Step "Instalando Arize Phoenix..."

$pipArgs = @("-m", "pip", "install")
if ($Upgrade) {
    $pipArgs += "--upgrade"
}
$pipArgs += @(
    "--quiet",
    "--disable-pip-version-check",
    "--only-binary", ":all:",
    "arize-phoenix",
    "arize-phoenix-otel>=0.16.0",
    "opentelemetry-api",
    "opentelemetry-sdk",
    "opentelemetry-exporter-otlp-proto-http"
)

# Usar Start-Process para evitar NativeCommandError no PS 5.1
$pipLogFile = Join-Path $WorkingDir "pip-install.log"
$pipErrFile = Join-Path $WorkingDir "pip-install-error.log"

$pipProcess = Start-Process -FilePath $script:PythonExe `
    -ArgumentList ((@($script:PythonArgs) + $pipArgs) | Where-Object { $_ }) `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $pipLogFile `
    -RedirectStandardError $pipErrFile

if ($pipProcess.ExitCode -ne 0) {
    # Tentar novamente sem --only-binary (permite compilacao se tiver build tools)
    Write-Warn "Falha com --only-binary. Tentando sem restricao de wheels..."
    $pipArgs = $pipArgs | Where-Object { $_ -ne "--only-binary" -and $_ -ne ":all:" }

    $pipProcess = Start-Process -FilePath $script:PythonExe `
        -ArgumentList ((@($script:PythonArgs) + $pipArgs) | Where-Object { $_ }) `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $pipLogFile `
        -RedirectStandardError $pipErrFile

    if ($pipProcess.ExitCode -ne 0) {
        Write-Fail "Falha na instalacao do Phoenix."
        Write-Host ""
        Write-Host "  Causa provavel: Python $pyVersion nao possui wheels pre-compiladas" -ForegroundColor Yellow
        Write-Host "  para todas as dependencias do Phoenix no Windows." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Solucoes:" -ForegroundColor White
        Write-Host "    1. Instale Python 3.12 (melhor compatibilidade de wheels):" -ForegroundColor DarkGray
        Write-Host "       winget install Python.Python.3.12" -ForegroundColor DarkGray
        Write-Host "       Depois re-execute: .\scripts\setup-phoenix.ps1 -Start" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    2. Se ja tem Python 3.12 instalado, o script usara" -ForegroundColor DarkGray
        Write-Host "       automaticamente via py launcher (py -3.12)." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Log de erro: $pipErrFile" -ForegroundColor DarkGray
        exit 1
    }
}

# Verificar instalação
$phoenixVersion = Invoke-Python @("-c", "import phoenix; print(phoenix.__version__)")
if (-not $phoenixVersion) {
    Write-Fail "Falha na instalacao do Phoenix (modulo nao encontrado apos pip install)"
    Write-Host "  Verifique o log: $pipErrFile" -ForegroundColor DarkGray
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
    $serveArgs = @("-m", "phoenix.server.main", "serve")
    if ($script:PythonArgs) { $serveArgs = @($script:PythonArgs) + $serveArgs }
    $phoenixProcess = Start-Process -FilePath $script:PythonExe -ArgumentList $serveArgs `
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
