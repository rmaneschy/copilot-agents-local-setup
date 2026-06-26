<#
.SYNOPSIS
    Habilita ou desabilita o monitoramento de ferramentas MCP.

.DESCRIPTION
    Alterna entre a configuração MCP padrão (sem proxy) e a configuração
    com proxy logger (com monitoramento). Modifica o .vscode/mcp.json
    do diretório global de configuração do Copilot.

.PARAMETER Enable
    Habilita o monitoramento (usa mcp-with-monitoring.json).

.PARAMETER Disable
    Desabilita o monitoramento (usa mcp.json padrão).

.PARAMETER Status
    Mostra o estado atual do monitoramento.

.EXAMPLE
    .\toggle-monitoring.ps1 -Enable
    .\toggle-monitoring.ps1 -Disable
    .\toggle-monitoring.ps1 -Status
#>

param(
    [switch]$Enable,
    [switch]$Disable,
    [switch]$Status
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path "$ProjectRoot\.vscode\mcp.json")) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

$McpDefault = "$ProjectRoot\.vscode\mcp.json"
$McpMonitored = "$ProjectRoot\.vscode\mcp-with-monitoring.json"
$McpBackup = "$ProjectRoot\.vscode\mcp-original.json"
$MetricsDir = "$env:USERPROFILE\.copilot-metrics"

function Get-MonitoringStatus {
    if (Test-Path $McpDefault) {
        $content = Get-Content $McpDefault -Raw
        if ($content -match "mcp-proxy-logger") {
            return "ENABLED"
        }
    }
    return "DISABLED"
}

if ($Status -or (-not $Enable -and -not $Disable)) {
    $currentStatus = Get-MonitoringStatus
    Write-Host ""
    Write-Host "  MCP Monitoring Status: " -NoNewline
    if ($currentStatus -eq "ENABLED") {
        Write-Host "$currentStatus" -ForegroundColor Green
    } else {
        Write-Host "$currentStatus" -ForegroundColor Yellow
    }
    Write-Host ""
    
    if (Test-Path "$MetricsDir\calls.jsonl") {
        $lineCount = (Get-Content "$MetricsDir\calls.jsonl" | Measure-Object -Line).Lines
        $fileSize = [math]::Round((Get-Item "$MetricsDir\calls.jsonl").Length / 1KB, 1)
        Write-Host "  Log: $MetricsDir\calls.jsonl"
        Write-Host "  Registros: $lineCount | Tamanho: ${fileSize}KB"
    } else {
        Write-Host "  Log: nenhum registro encontrado"
    }
    Write-Host ""
    Write-Host "  Uso:"
    Write-Host "    .\toggle-monitoring.ps1 -Enable    # Habilitar monitoramento"
    Write-Host "    .\toggle-monitoring.ps1 -Disable   # Desabilitar monitoramento"
    Write-Host "    .\generate-dashboard.ps1           # Gerar dashboard HTML"
    Write-Host ""
    return
}

if ($Enable) {
    if (-not (Test-Path $McpMonitored)) {
        Write-Host "[ERRO] Arquivo mcp-with-monitoring.json nao encontrado." -ForegroundColor Red
        exit 1
    }
    
    # Backup do original
    if ((Test-Path $McpDefault) -and -not (Test-Path $McpBackup)) {
        Copy-Item $McpDefault $McpBackup -Force
        Write-Host "[INFO] Backup salvo em: $McpBackup" -ForegroundColor Cyan
    }
    
    # Ativar monitoramento
    Copy-Item $McpMonitored $McpDefault -Force
    
    # Criar diretório de métricas
    New-Item -ItemType Directory -Force -Path $MetricsDir | Out-Null
    
    Write-Host "[OK] Monitoramento HABILITADO." -ForegroundColor Green
    Write-Host "[INFO] Reinicie o IDE para aplicar as alteracoes." -ForegroundColor Cyan
    Write-Host "[INFO] Logs serao gravados em: $MetricsDir\calls.jsonl" -ForegroundColor Cyan
}

if ($Disable) {
    if (Test-Path $McpBackup) {
        Copy-Item $McpBackup $McpDefault -Force
        Write-Host "[OK] Monitoramento DESABILITADO (restaurado backup)." -ForegroundColor Green
    } else {
        # Restaurar do template original (aliases genéricos)
        $originalMcp = @'
{
  "inputs": [],
  "servers": {
    "code-search": {
      "type": "stdio",
      "command": "codebase-memory-mcp",
      "args": []
    },
    "code-navigation": {
      "command": "serena",
      "args": ["start-mcp-server", "--context=vscode"]
    }
  }
}
'@
        $originalMcp | Set-Content -Path $McpDefault -Encoding UTF8
        Write-Host "[OK] Monitoramento DESABILITADO (restaurado padrao)." -ForegroundColor Green
    }
    Write-Host "[INFO] Reinicie o IDE para aplicar as alteracoes." -ForegroundColor Cyan
    Write-Host "[INFO] Os logs existentes foram preservados em: $MetricsDir" -ForegroundColor Cyan
}
