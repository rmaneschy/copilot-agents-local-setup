<#
.SYNOPSIS
    Aplica otimizações de desempenho ao ambiente RAG + Serena.

.DESCRIPTION
    Este script configura Ollama keep-alive, cria índices no LanceDB,
    executa compactação e aquece os componentes para uso imediato.

.PARAMETER CreateIndexes
    Cria índices vetoriais e escalares no LanceDB.

.PARAMETER Compact
    Executa compactação e limpeza de versões antigas no LanceDB.

.PARAMETER WarmUp
    Configura keep-alive e aquece o modelo de embeddings.

.PARAMETER All
    Executa todas as otimizações.

.EXAMPLE
    .\optimize-environment.ps1 -All
    .\optimize-environment.ps1 -WarmUp
    .\optimize-environment.ps1 -CreateIndexes -Compact
#>

param(
    [switch]$CreateIndexes,
    [switch]$Compact,
    [switch]$WarmUp,
    [switch]$All
)

$ErrorActionPreference = "Stop"

if (-not ($CreateIndexes -or $Compact -or $WarmUp -or $All)) {
    Write-Host "Uso: .\optimize-environment.ps1 -All" -ForegroundColor Yellow
    Write-Host "     .\optimize-environment.ps1 -WarmUp"
    Write-Host "     .\optimize-environment.ps1 -CreateIndexes -Compact"
    Write-Host ""
    Write-Host "Flags disponíveis:" -ForegroundColor Cyan
    Write-Host "  -WarmUp        Configura keep-alive e aquece Ollama"
    Write-Host "  -CreateIndexes Cria índices vetoriais e escalares no LanceDB"
    Write-Host "  -Compact       Compacta fragmentos e limpa versões antigas"
    Write-Host "  -All           Executa todas as otimizações"
    exit 0
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Otimização de Ambiente RAG + Serena" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$dbPath = Join-Path $env:USERPROFILE ".copilot-rag\lancedb"

# ─────────────────────────────────────────────
# ETAPA 1: Ollama Keep-Alive e Warm-Up
# ─────────────────────────────────────────────
if ($All -or $WarmUp) {
    Write-Host "[1/4] Configurando Ollama keep-alive..." -ForegroundColor Cyan

    $currentKeepAlive = [System.Environment]::GetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "User")
    if ($currentKeepAlive -ne "-1") {
        [System.Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "-1", "User")
        Write-Host "  Variável OLLAMA_KEEP_ALIVE definida como '-1' (permanente)" -ForegroundColor Green
    } else {
        Write-Host "  OLLAMA_KEEP_ALIVE já configurado" -ForegroundColor Gray
    }

    Write-Host "  Aquecendo modelo de embeddings..."
    $body = @{ model = "nomic-embed-text"; prompt = "warmup query for model initialization" } | ConvertTo-Json
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-RestMethod -Uri "http://localhost:11434/api/embeddings" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30 | Out-Null
        $stopwatch.Stop()
        $elapsed = $stopwatch.ElapsedMilliseconds
        Write-Host "  OK - Modelo carregado em ${elapsed}ms" -ForegroundColor Green
    } catch {
        Write-Host "  AVISO - Ollama não está rodando. Inicie com 'ollama serve'" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ─────────────────────────────────────────────
# ETAPA 2: Índices LanceDB
# ─────────────────────────────────────────────
if ($All -or $CreateIndexes) {
    Write-Host "[2/4] Criando índices no LanceDB..." -ForegroundColor Cyan

    if (-not (Test-Path $dbPath)) {
        Write-Host "  SKIP - Banco não encontrado em $dbPath" -ForegroundColor Yellow
        Write-Host "  Execute index-workspace.ps1 primeiro." -ForegroundColor Yellow
    } else {
        $pythonScript = @"
import lancedb
import math
import sys

db_path = r'$dbPath'
try:
    db = lancedb.connect(db_path)
    table = db.open_table('code_chunks')
    row_count = table.count_rows()
    print(f'  Tabela: {row_count:,} chunks indexados')

    # Indice vetorial
    if row_count > 100000:
        print('  Criando indice vetorial IVF_PQ...')
        num_partitions = min(int(math.sqrt(row_count)), 512)
        table.create_index(
            metric='cosine',
            num_partitions=num_partitions,
            num_sub_vectors=48,
            index_type='IVF_PQ',
            replace=True
        )
        print(f'  OK - Indice vetorial criado ({num_partitions} particoes)')
    else:
        print(f'  SKIP - {row_count:,} chunks < 100K, brute-force e suficiente')

    # Indices escalares
    print('  Criando indices escalares...')
    columns = [col for col in table.schema.names if col != 'vector']
    created = 0
    for col in ['file_path', 'repository', 'language']:
        if col in columns:
            try:
                idx_type = 'BITMAP' if col == 'language' else 'BTREE'
                table.create_index(col, index_type=idx_type, replace=True)
                created += 1
            except Exception as e:
                print(f'  AVISO - Indice {col}: {e}')
    print(f'  OK - {created} indices escalares criados')

except FileNotFoundError:
    print('  SKIP - Tabela code_chunks nao encontrada.')
except Exception as e:
    print(f'  ERRO - {e}')
    sys.exit(1)
"@
        $pythonScript | python -
    }
    Write-Host ""
}

# ─────────────────────────────────────────────
# ETAPA 3: Compactação LanceDB
# ─────────────────────────────────────────────
if ($All -or $Compact) {
    Write-Host "[3/4] Compactando LanceDB..." -ForegroundColor Cyan

    if (-not (Test-Path $dbPath)) {
        Write-Host "  SKIP - Banco não encontrado em $dbPath" -ForegroundColor Yellow
    } else {
        $pythonScript = @"
import lancedb
from datetime import timedelta

db_path = r'$dbPath'
try:
    db = lancedb.connect(db_path)
    table = db.open_table('code_chunks')

    before_fragments = len(table.to_lance().get_fragments())
    table.optimize(cleanup_older_than=timedelta(days=7))
    after_fragments = len(table.to_lance().get_fragments())

    reduced = before_fragments - after_fragments
    if reduced > 0:
        print(f'  OK - Compactacao: {before_fragments} -> {after_fragments} fragmentos (-{reduced})')
    else:
        print(f'  OK - Banco ja otimizado ({after_fragments} fragmentos)')

except FileNotFoundError:
    print('  SKIP - Tabela code_chunks nao encontrada.')
except Exception as e:
    print(f'  AVISO - {e}')
"@
        $pythonScript | python -
    }
    Write-Host ""
}

# ─────────────────────────────────────────────
# ETAPA 4: Resumo Final
# ─────────────────────────────────────────────
Write-Host "[4/4] Estado do ambiente..." -ForegroundColor Cyan
Write-Host ""

$keepAlive = [System.Environment]::GetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "User")
$ollamaStatus = if ($keepAlive -eq "-1") { "Permanente (-1)" } else { "Padrão (5min)" }

Write-Host "  ┌─────────────────────────────────────────────┐"
Write-Host "  │ Ollama keep-alive:  $ollamaStatus"
Write-Host "  │ LanceDB path:       $dbPath"
if (Test-Path $dbPath) {
    Write-Host "  │ LanceDB status:     Disponível" -ForegroundColor Green
} else {
    Write-Host "  │ LanceDB status:     Não inicializado" -ForegroundColor Yellow
}
Write-Host "  └─────────────────────────────────────────────┘"
Write-Host ""
Write-Host "Otimização concluída!" -ForegroundColor Green
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Yellow
Write-Host "  1. Reinicie o Ollama para aplicar keep-alive (se alterado)"
Write-Host "  2. Abra os projetos principais no IntelliJ (warm-up LSP)"
Write-Host "  3. Verifique saúde: .\scripts\health-check.ps1"
Write-Host ""
