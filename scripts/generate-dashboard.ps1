<#
.SYNOPSIS
    Gera um dashboard HTML estático a partir dos logs de uso das ferramentas MCP.

.DESCRIPTION
    Lê o arquivo ~/.copilot-metrics/calls.jsonl e gera um relatório visual
    em HTML com gráficos (Chart.js via CDN) mostrando:
    - Total de chamadas por server (Serena vs RAG)
    - Top 10 tools mais utilizadas
    - Tempo médio de resposta por tool
    - Taxa de erro por server
    - Timeline de uso (últimas 24h, 7 dias, 30 dias)
    - Gargalos identificados (chamadas > 5s)

.PARAMETER Days
    Número de dias de histórico a considerar. Padrão: 7.

.PARAMETER OutputPath
    Caminho do arquivo HTML gerado. Padrão: ~/.copilot-metrics/dashboard.html

.EXAMPLE
    .\generate-dashboard.ps1
    .\generate-dashboard.ps1 -Days 30
    .\generate-dashboard.ps1 -OutputPath "C:\reports\dashboard.html"
#>

param(
    [int]$Days = 7,
    [string]$OutputPath = "$env:USERPROFILE\.copilot-metrics\dashboard.html"
)

$ErrorActionPreference = "Stop"

# --- Configuração ---
$MetricsDir = "$env:USERPROFILE\.copilot-metrics"
$CallsLog = "$MetricsDir\calls.jsonl"

# --- Validação ---
if (-not (Test-Path $CallsLog)) {
    Write-Host "[WARN] Arquivo de logs nao encontrado: $CallsLog" -ForegroundColor Yellow
    Write-Host "[INFO] O dashboard sera gerado com dados de exemplo para demonstracao." -ForegroundColor Cyan
    
    # Gerar dados de exemplo para demonstração
    $sampleData = @()
    $tools = @("activate_project", "get_symbol_overview", "find_symbol", "find_referencing_symbols", "find_implementations", "search_codebase", "find_declaration")
    $servers = @("serena", "serena", "serena", "serena", "serena", "local-code-rag", "serena")
    
    for ($i = 0; $i -lt 50; $i++) {
        $idx = Get-Random -Minimum 0 -Maximum $tools.Count
        $sampleData += @{
            timestamp   = (Get-Date).AddHours(-(Get-Random -Minimum 1 -Maximum ($Days * 24))).ToUniversalTime().ToString("o")
            server      = $servers[$idx]
            method      = "tools/call"
            tool        = $tools[$idx]
            duration_ms = [math]::Round((Get-Random -Minimum 50 -Maximum 8000), 2)
            success     = ((Get-Random -Minimum 0 -Maximum 10) -gt 1)
            error       = $null
        }
    }
    
    New-Item -ItemType Directory -Force -Path $MetricsDir | Out-Null
    $sampleData | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -Path $CallsLog -Encoding UTF8
    Write-Host "[INFO] Dados de exemplo gerados em: $CallsLog" -ForegroundColor Green
}

# --- Leitura dos Logs ---
Write-Host "[INFO] Lendo logs de $CallsLog..." -ForegroundColor Cyan

$cutoffDate = (Get-Date).AddDays(-$Days).ToUniversalTime()
$allCalls = @()

Get-Content $CallsLog -Encoding UTF8 | ForEach-Object {
    try {
        $entry = $_ | ConvertFrom-Json
        $entryDate = [DateTime]::Parse($entry.timestamp).ToUniversalTime()
        if ($entryDate -ge $cutoffDate) {
            $allCalls += $entry
        }
    } catch {
        # Ignora linhas malformadas
    }
}

Write-Host "[INFO] $($allCalls.Count) chamadas encontradas nos ultimos $Days dias." -ForegroundColor Green

# --- Cálculo de Métricas ---

# Total por server
$byServer = $allCalls | Group-Object -Property server | ForEach-Object {
    @{ name = $_.Name; count = $_.Count }
}

# Top tools
$byTool = $allCalls | Group-Object -Property tool | Sort-Object -Property Count -Descending | Select-Object -First 10 | ForEach-Object {
    @{ name = $_.Name; count = $_.Count }
}

# Tempo médio por tool
$avgDuration = $allCalls | Group-Object -Property tool | ForEach-Object {
    $avg = ($_.Group | Measure-Object -Property duration_ms -Average).Average
    @{ name = $_.Name; avg_ms = [math]::Round($avg, 1) }
} | Sort-Object { $_.avg_ms } -Descending

# Taxa de erro
$errorRate = $allCalls | Group-Object -Property server | ForEach-Object {
    $total = $_.Count
    $errors = ($_.Group | Where-Object { -not $_.success }).Count
    @{ name = $_.Name; total = $total; errors = $errors; rate = if ($total -gt 0) { [math]::Round(($errors / $total) * 100, 1) } else { 0 } }
}

# Gargalos (> 5000ms)
$bottlenecks = $allCalls | Where-Object { $_.duration_ms -gt 5000 } | Sort-Object -Property duration_ms -Descending | Select-Object -First 20

# Timeline por hora (últimas 24h)
$last24h = $allCalls | Where-Object { 
    [DateTime]::Parse($_.timestamp).ToUniversalTime() -ge (Get-Date).AddHours(-24).ToUniversalTime() 
}
$hourlyData = @{}
0..23 | ForEach-Object { $hourlyData[$_] = 0 }
$last24h | ForEach-Object {
    $hour = [DateTime]::Parse($_.timestamp).ToLocalTime().Hour
    $hourlyData[$hour]++
}

# --- Geração do HTML ---
Write-Host "[INFO] Gerando dashboard HTML..." -ForegroundColor Cyan

$serverLabels = ($byServer | ForEach-Object { "'$($_.name)'" }) -join ","
$serverCounts = ($byServer | ForEach-Object { $_.count }) -join ","

$toolLabels = ($byTool | ForEach-Object { "'$($_.name)'" }) -join ","
$toolCounts = ($byTool | ForEach-Object { $_.count }) -join ","

$durationLabels = ($avgDuration | ForEach-Object { "'$($_.name)'" }) -join ","
$durationValues = ($avgDuration | ForEach-Object { $_.avg_ms }) -join ","

$hourLabels = (0..23 | ForEach-Object { "'${_}h'" }) -join ","
$hourValues = (0..23 | ForEach-Object { $hourlyData[$_] }) -join ","

$errorTableRows = ($errorRate | ForEach-Object {
    "<tr><td>$($_.name)</td><td>$($_.total)</td><td>$($_.errors)</td><td class=`"$(if ($_.rate -gt 10) {'text-red'} else {'text-green'})`">$($_.rate)%</td></tr>"
}) -join "`n"

$bottleneckRows = ($bottlenecks | ForEach-Object {
    $ts = [DateTime]::Parse($_.timestamp).ToLocalTime().ToString("dd/MM HH:mm")
    "<tr><td>$ts</td><td>$($_.server)</td><td>$($_.tool)</td><td class=`"text-red`">$([math]::Round($_.duration_ms / 1000, 2))s</td></tr>"
}) -join "`n"

$totalCalls = $allCalls.Count
$avgResponseTime = if ($allCalls.Count -gt 0) { [math]::Round(($allCalls | Measure-Object -Property duration_ms -Average).Average, 0) } else { 0 }
$totalErrors = ($allCalls | Where-Object { -not $_.success }).Count
$totalBottlenecks = ($allCalls | Where-Object { $_.duration_ms -gt 5000 }).Count

$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MCP Tools Dashboard - Copilot Agents</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0d1117; color: #c9d1d9; padding: 24px;
        }
        .header { 
            display: flex; justify-content: space-between; align-items: center;
            margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid #21262d;
        }
        .header h1 { font-size: 24px; color: #f0f6fc; }
        .header .meta { font-size: 13px; color: #8b949e; }
        .kpi-grid { 
            display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 24px;
        }
        .kpi-card {
            background: #161b22; border: 1px solid #21262d; border-radius: 8px;
            padding: 20px; text-align: center;
        }
        .kpi-card .value { font-size: 32px; font-weight: 700; color: #f0f6fc; }
        .kpi-card .label { font-size: 13px; color: #8b949e; margin-top: 4px; }
        .kpi-card.warning .value { color: #f85149; }
        .charts-grid {
            display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 24px;
        }
        .chart-card {
            background: #161b22; border: 1px solid #21262d; border-radius: 8px; padding: 20px;
        }
        .chart-card h3 { font-size: 14px; color: #f0f6fc; margin-bottom: 12px; }
        .chart-card canvas { max-height: 280px; }
        .full-width { grid-column: span 2; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; }
        th { text-align: left; padding: 10px 12px; background: #21262d; color: #f0f6fc; }
        td { padding: 8px 12px; border-bottom: 1px solid #21262d; }
        .text-red { color: #f85149; font-weight: 600; }
        .text-green { color: #3fb950; font-weight: 600; }
        .section-title { font-size: 18px; color: #f0f6fc; margin: 24px 0 12px; }
        @media (max-width: 768px) {
            .kpi-grid { grid-template-columns: repeat(2, 1fr); }
            .charts-grid { grid-template-columns: 1fr; }
            .full-width { grid-column: span 1; }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>MCP Tools Dashboard</h1>
        <div class="meta">
            Periodo: ultimos $Days dias | Gerado em: $(Get-Date -Format "dd/MM/yyyy HH:mm") | 
            Fonte: ~/.copilot-metrics/calls.jsonl
        </div>
    </div>

    <!-- KPIs -->
    <div class="kpi-grid">
        <div class="kpi-card">
            <div class="value">$totalCalls</div>
            <div class="label">Total de Chamadas</div>
        </div>
        <div class="kpi-card">
            <div class="value">${avgResponseTime}ms</div>
            <div class="label">Tempo Medio de Resposta</div>
        </div>
        <div class="kpi-card $(if ($totalErrors -gt 0) {'warning'})">
            <div class="value">$totalErrors</div>
            <div class="label">Erros Registrados</div>
        </div>
        <div class="kpi-card $(if ($totalBottlenecks -gt 0) {'warning'})">
            <div class="value">$totalBottlenecks</div>
            <div class="label">Gargalos (&gt; 5s)</div>
        </div>
    </div>

    <!-- Charts -->
    <div class="charts-grid">
        <div class="chart-card">
            <h3>Chamadas por Server</h3>
            <canvas id="serverChart"></canvas>
        </div>
        <div class="chart-card">
            <h3>Top 10 Tools Mais Utilizadas</h3>
            <canvas id="toolChart"></canvas>
        </div>
        <div class="chart-card">
            <h3>Tempo Medio por Tool (ms)</h3>
            <canvas id="durationChart"></canvas>
        </div>
        <div class="chart-card">
            <h3>Atividade nas Ultimas 24h</h3>
            <canvas id="timelineChart"></canvas>
        </div>
    </div>

    <!-- Tabelas -->
    <h2 class="section-title">Taxa de Erro por Server</h2>
    <div class="chart-card" style="margin-bottom: 24px;">
        <table>
            <thead><tr><th>Server</th><th>Total</th><th>Erros</th><th>Taxa</th></tr></thead>
            <tbody>$errorTableRows</tbody>
        </table>
    </div>

    <h2 class="section-title">Gargalos Identificados (chamadas &gt; 5s)</h2>
    <div class="chart-card">
        <table>
            <thead><tr><th>Data/Hora</th><th>Server</th><th>Tool</th><th>Duracao</th></tr></thead>
            <tbody>$(if ($bottleneckRows) { $bottleneckRows } else { '<tr><td colspan="4" style="text-align:center;color:#3fb950;">Nenhum gargalo identificado</td></tr>' })</tbody>
        </table>
    </div>

    <script>
        const chartDefaults = {
            color: '#c9d1d9',
            borderColor: '#21262d',
        };
        Chart.defaults.color = '#c9d1d9';

        // Server Chart (Doughnut)
        new Chart(document.getElementById('serverChart'), {
            type: 'doughnut',
            data: {
                labels: [$serverLabels],
                datasets: [{
                    data: [$serverCounts],
                    backgroundColor: ['#8957e5', '#f78166', '#3fb950', '#58a6ff'],
                    borderWidth: 0
                }]
            },
            options: { plugins: { legend: { position: 'bottom' } } }
        });

        // Tool Chart (Bar Horizontal)
        new Chart(document.getElementById('toolChart'), {
            type: 'bar',
            data: {
                labels: [$toolLabels],
                datasets: [{
                    data: [$toolCounts],
                    backgroundColor: '#58a6ff',
                    borderRadius: 4
                }]
            },
            options: {
                indexAxis: 'y',
                plugins: { legend: { display: false } },
                scales: { x: { grid: { color: '#21262d' } }, y: { grid: { display: false } } }
            }
        });

        // Duration Chart (Bar)
        new Chart(document.getElementById('durationChart'), {
            type: 'bar',
            data: {
                labels: [$durationLabels],
                datasets: [{
                    data: [$durationValues],
                    backgroundColor: (ctx) => ctx.raw > 5000 ? '#f85149' : ctx.raw > 2000 ? '#f78166' : '#3fb950',
                    borderRadius: 4
                }]
            },
            options: {
                indexAxis: 'y',
                plugins: { legend: { display: false } },
                scales: { x: { grid: { color: '#21262d' } }, y: { grid: { display: false } } }
            }
        });

        // Timeline Chart (Line)
        new Chart(document.getElementById('timelineChart'), {
            type: 'line',
            data: {
                labels: [$hourLabels],
                datasets: [{
                    data: [$hourValues],
                    borderColor: '#58a6ff',
                    backgroundColor: 'rgba(88, 166, 255, 0.1)',
                    fill: true,
                    tension: 0.3,
                    pointRadius: 3
                }]
            },
            options: {
                plugins: { legend: { display: false } },
                scales: {
                    x: { grid: { color: '#21262d' } },
                    y: { grid: { color: '#21262d' }, beginAtZero: true }
                }
            }
        });
    </script>
</body>
</html>
"@

# --- Salvar HTML ---
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$html | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "[OK] Dashboard gerado em: $OutputPath" -ForegroundColor Green
Write-Host "[INFO] Abra no navegador: start `"$OutputPath`"" -ForegroundColor Cyan
