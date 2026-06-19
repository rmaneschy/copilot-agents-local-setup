# Guia de Otimização de Desempenho: Compozy + RAG + Serena

## Introdução

A integração entre Compozy, RAG Vetorial e Serena MCP cria um pipeline com múltiplas camadas de processamento. Cada camada introduz latência e consome recursos. Este guia apresenta técnicas práticas para otimizar o desempenho de ponta a ponta, reduzindo tempos de resposta, consumo de tokens e uso de memória — tudo dentro das restrições de uma máquina Windows 11 sem admin e sem Docker.

> "The model isn't the bottleneck. The layer between it and your data is."
> — CData Engineering, "Proven MCP Performance Optimization Techniques" [1]

---

## Anatomia dos Gargalos

Antes de otimizar, é fundamental entender onde o tempo é gasto. O pipeline completo de uma query envolve 5 estágios:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  QUERY DO USUÁRIO                                                       │
│  "Quais serviços gravam na base de pedidos?"                            │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ESTÁGIO 1: Embedding da Query                                          │
│  Ollama (nomic-embed-text) → vetor 768d                                 │
│  Latência típica: 200-500ms (cold) | 50-100ms (warm)                    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ESTÁGIO 2: Busca Vetorial                                              │
│  LanceDB → top-K chunks relevantes                                      │
│  Latência típica: 5-50ms (com índice) | 200-2000ms (brute-force)        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ESTÁGIO 3: Navegação Semântica                                         │
│  Serena MCP → símbolos, referências, declarações                        │
│  Latência típica: 100-300ms (warm LSP) | 2-5s (cold start)              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ESTÁGIO 4: Composição de Contexto                                      │
│  Compozy/Copilot → monta prompt com evidências                          │
│  Latência típica: 10-50ms                                               │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ESTÁGIO 5: Inferência do LLM                                           │
│  GitHub Copilot → resposta final                                        │
│  Latência típica: 2-10s (depende do modelo e tokens)                    │
└─────────────────────────────────────────────────────────────────────────┘
```

| Estágio | Componente | Gargalo Principal | Impacto |
| :--- | :--- | :--- | :--- |
| 1 | Ollama | Cold start do modelo | +400ms na primeira query |
| 2 | LanceDB | Brute-force sem índice | +2s em codebases >100K chunks |
| 3 | Serena | LSP cold start por projeto | +5s na primeira navegação |
| 4 | Compozy | Contexto excessivo | Tokens desperdiçados |
| 5 | LLM | Context window saturada | Respostas lentas e imprecisas |

---

## Otimização por Camada

### Camada 1: Ollama — Embeddings Locais

O Ollama processa embeddings de forma serial (single-thread por design) [2]. A principal otimização é **manter o modelo em memória** entre chamadas.

#### 1.1 Keep-Alive Permanente

Por padrão, o Ollama descarrega o modelo após 5 minutos de inatividade. Configure para manter indefinidamente:

```powershell
# Definir variável de ambiente (persistente)
[System.Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "-1", "User")

# Ou por sessão
$env:OLLAMA_KEEP_ALIVE = "-1"
ollama serve
```

**Impacto**: Elimina o cold start de ~400ms em queries subsequentes. O modelo permanece em VRAM/RAM até o Ollama ser encerrado.

#### 1.2 Pré-aquecimento na Inicialização

Adicione ao script de startup do ambiente:

```powershell
# warm-up.ps1 — Executar ao iniciar o dia de trabalho
Write-Host "Aquecendo modelo de embeddings..."
$body = @{ model = "nomic-embed-text"; prompt = "warmup" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:11434/api/embeddings" -Method Post -Body $body -ContentType "application/json" | Out-Null
Write-Host "Modelo carregado em memória."
```

#### 1.3 Batch de Embeddings na Indexação

Ao indexar o workspace, agrupe textos em lotes maiores para reduzir overhead de chamadas HTTP:

```python
# Em vez de 1 embedding por vez:
# for chunk in chunks: embed(chunk)  # LENTO

# Processar em lotes de 32-64 chunks:
BATCH_SIZE = 32
for i in range(0, len(chunks), BATCH_SIZE):
    batch = chunks[i:i+BATCH_SIZE]
    # Ollama processa sequencialmente internamente,
    # mas reduz overhead HTTP de N chamadas para N/32
    embeddings = [embed(chunk) for chunk in batch]
    db.add(embeddings)
```

**Nota**: O Ollama processa embeddings sequencialmente mesmo em batch [2], mas agrupar reduz o overhead de serialização JSON e round-trips HTTP.

#### 1.4 Dimensão e Quantização do Modelo

O `nomic-embed-text` suporta Matryoshka Representation Learning, permitindo truncar dimensões sem retreinar:

| Configuração | Dimensões | RAM | Qualidade | Velocidade |
| :--- | :--- | :--- | :--- | :--- |
| Full (padrão) | 768 | ~270MB | 100% | Baseline |
| Truncado | 512 | ~180MB | ~97% | +20% |
| Truncado | 256 | ~90MB | ~92% | +40% |

Para codebases onde precisão absoluta não é crítica (busca exploratória), considere truncar para 512 dimensões:

```python
# No script de indexação, truncar o vetor
embedding = ollama.embed(text)[:512]
```

---

### Camada 2: LanceDB — Busca Vetorial

O LanceDB é performante por padrão até ~100K vetores (brute-force scan) [3]. Acima disso, índices são essenciais.

#### 2.1 Criar Índices Vetoriais

Após a indexação inicial do workspace, crie um índice IVF_PQ:

```python
import lancedb

db = lancedb.connect("~/.copilot-rag/lancedb")
table = db.open_table("code_chunks")

# Criar índice vetorial (recomendado acima de 100K chunks)
table.create_index(
    metric="cosine",           # nomic-embed-text usa cosine
    num_partitions=256,        # sqrt(N) é uma boa heurística
    num_sub_vectors=48,        # 768 / 16 = 48 sub-vetores
    index_type="IVF_PQ"
)
```

**Impacto**: Reduz comparações vetoriais de N para ~N/256 × nprobes. Em um workspace com 500K chunks, passa de 500K comparações para ~40K (~12x mais rápido).

#### 2.2 Criar Índices Escalares

Para filtros por linguagem, repositório ou caminho:

```python
# Índice para filtrar por repositório
table.create_index("repository", index_type="BTREE")

# Índice para filtrar por linguagem (baixa cardinalidade)
table.create_index("language", index_type="BITMAP")

# Índice para tags (array)
table.create_index("tags", index_type="LABEL_LIST")
```

**Impacto**: Queries como "busque apenas em order-service" usam o índice escalar antes da busca vetorial, reduzindo drasticamente o espaço de busca.

#### 2.3 Compactação Periódica

Cada `add()` cria um novo fragmento. Muitos fragmentos pequenos degradam a performance:

```python
from datetime import timedelta

# Executar semanalmente ou após grandes indexações
table.optimize(cleanup_older_than=timedelta(days=7))
```

Adicione ao `index-workspace.ps1`:

```powershell
# Após indexação, otimizar o banco
Write-Host "Compactando LanceDB..."
python -c "
import lancedb
from datetime import timedelta
db = lancedb.connect('$env:USERPROFILE\.copilot-rag\lancedb')
table = db.open_table('code_chunks')
table.optimize(cleanup_older_than=timedelta(days=7))
print('Compactação concluída.')
"
```

#### 2.4 Projeção e Limite Explícitos

Sempre especificar quais colunas retornar e limitar resultados:

```python
# RUIM: retorna todas as colunas de todos os matches
results = table.search(query_vector).to_list()

# BOM: retorna apenas o necessário
results = (
    table.search(query_vector)
    .select(["file_path", "content", "symbol_name"])
    .limit(20)
    .to_list()
)
```

**Impacto**: Reduz I/O e memória. Em vez de carregar vetores de 768d + metadados completos, carrega apenas texto e caminhos.

#### 2.5 Indexação Incremental

Não reindexe o workspace inteiro a cada execução:

```powershell
# index-workspace.ps1 com modo incremental
param(
    [switch]$Full,
    [int]$SinceHours = 24
)

if ($Full) {
    Write-Host "Indexação completa..."
    # Reindexar tudo
} else {
    Write-Host "Indexação incremental (últimas $SinceHours horas)..."
    $since = (Get-Date).AddHours(-$SinceHours)
    # Indexar apenas arquivos modificados após $since
    Get-ChildItem -Path $WorkspacePath -Recurse -File |
        Where-Object { $_.LastWriteTime -gt $since } |
        ForEach-Object { Index-File $_.FullName }
}
```

**Impacto**: Reduz tempo de indexação de minutos para segundos no dia a dia.

---

### Camada 3: Serena MCP — Navegação por Símbolo

O Serena depende do Language Server Protocol (LSP), que precisa de um projeto "ativado" para funcionar.

#### 3.1 Warm-Up do LSP

O maior gargalo do Serena é o cold start do Language Server (~2-5s para Java/TypeScript). Mitigue com ativação antecipada:

```powershell
# No início do dia, ativar os projetos mais usados
$projects = @(
    "C:\Users\$env:USERNAME\workspace\order-service",
    "C:\Users\$env:USERNAME\workspace\payment-service",
    "C:\Users\$env:USERNAME\workspace\gateway"
)

foreach ($project in $projects) {
    Write-Host "Ativando LSP para $(Split-Path $project -Leaf)..."
    # O Serena mantém o LSP ativo após primeira ativação
    # Simular uma chamada de ativação via MCP
}
```

Na prática, abrir o projeto no IntelliJ já inicia o LSP. A recomendação é: **abra todos os projetos relevantes antes de usar os agentes**.

#### 3.2 Priorizar Serena para Queries Determinísticas

O Serena retorna resultados **determinísticos** (mesma query = mesmo resultado), enquanto o RAG retorna resultados **probabilísticos**. Use essa propriedade para cache:

| Tipo de Query | Ferramenta Ideal | Cacheável? |
| :--- | :--- | :--- |
| "Quem chama o método X?" | Serena (`find_referencing_symbols`) | Sim (até próximo commit) |
| "Onde a senha é validada?" | RAG (busca semântica) | Parcialmente |
| "Qual a interface do serviço Y?" | Serena (`get_symbol_overview`) | Sim |
| "Padrões de tratamento de erro" | RAG (busca por conceito) | Parcialmente |

#### 3.3 Limitar Escopo de Navegação

Ao usar o Serena em codebases grandes, limite o escopo:

```markdown
<!-- No prompt do agente, ser específico -->
Use `serena/activate_project` apenas para o serviço alvo.
Não navegue para dependências externas (libs, frameworks).
Limite `find_referencing_symbols` a 3 níveis de profundidade.
```

---

### Camada 4: Compozy — Orquestração

#### 4.1 Progressive Disclosure de Tools

A Anthropic demonstrou que expor todas as tool definitions ao modelo consome tokens desnecessários [4]. O Compozy mitiga isso naturalmente com seus Reusable Agents — cada agente vê apenas os MCP servers declarados em seu `mcp.json`.

**Princípio**: Não declare `local-code-rag` em agentes que não precisam de busca semântica (ex: um agente de formatação de código).

```toml
# .compozy/agents/code-formatter/mcp.json
{
  "servers": {
    "serena": { ... }
    # NÃO incluir local-code-rag — este agente não precisa
  }
}
```

#### 4.2 Memória Compactada entre Tasks

O Compozy mantém memória entre tasks via arquivos `.md` no diretório `.compozy/memory/`. Otimize o tamanho:

```toml
# .compozy/config.toml
[memory]
max_context_tokens = 4000    # Limitar contexto herdado
compaction_strategy = "summary"  # Resumir em vez de copiar integralmente
```

**Impacto**: Tasks posteriores recebem um resumo de ~4K tokens das decisões anteriores, em vez de logs completos de ~20K tokens.

#### 4.3 Paralelização de Tasks Independentes

Quando o Compozy decompõe um PRD em tasks, identifique quais são independentes:

```markdown
## Tasks (com dependências)
1. [x] Criar tipagens TypeScript          ← independente
2. [x] Criar migration de banco           ← independente
3. [ ] Implementar repository (depende: 1, 2)
4. [ ] Implementar service (depende: 3)
5. [ ] Implementar controller (depende: 4)
```

Tasks 1 e 2 podem ser executadas em paralelo:

```powershell
# Executar tasks independentes em paralelo
compozy tasks run --ids 1,2 --parallel
```

#### 4.4 Cache de Contexto do Codebase

O enrichment do Compozy (exploração do codebase antes de gerar tasks) pode ser cacheado:

```toml
# .compozy/config.toml
[enrichment]
cache_ttl = "4h"           # Cache válido por 4 horas
cache_dir = ".compozy/cache"
invalidate_on = ["git_commit"]  # Invalidar após commits
```

---

### Camada 5: Redução de Tokens no LLM

#### 5.1 Filtragem de Resultados Antes do LLM

O padrão da Anthropic de "Code Execution with MCP" [4] aplica-se aqui: filtre dados no MCP server antes de enviá-los ao modelo.

```python
# No mcp-proxy-logger.py ou no próprio MCP server
# Em vez de retornar 50 chunks de 500 tokens cada (25K tokens):
results = search(query, limit=50)

# Filtrar e resumir antes de retornar ao modelo (5K tokens):
filtered = [r for r in results if r["relevance"] > 0.7][:10]
summarized = [{"file": r["file"], "snippet": r["content"][:200]} for r in filtered]
return summarized
```

#### 5.2 Structured Output nos MCP Servers

Configure os MCP servers para retornar dados estruturados em vez de texto livre:

```json
// Resposta otimizada do RAG
{
  "matches": [
    {
      "file": "order-service/src/main/java/com/app/repository/OrderRepository.java",
      "line": 42,
      "symbol": "saveOrder",
      "relevance": 0.92,
      "snippet": "public Order saveOrder(Order order) { return jdbcTemplate.update(...) }"
    }
  ],
  "total_matches": 47,
  "returned": 5
}
```

Em vez de:

```text
Encontrei 47 resultados. O arquivo order-service/src/main/java/com/app/repository/OrderRepository.java
na linha 42 contém o método saveOrder que parece relevante porque ele usa jdbcTemplate para persistir...
(texto livre consumindo 3x mais tokens)
```

---

## Script de Otimização Automatizada

O script abaixo aplica todas as otimizações de infraestrutura de uma vez:

```powershell
# optimize-environment.ps1
# Aplica otimizações de desempenho ao ambiente RAG + Serena

param(
    [switch]$CreateIndexes,
    [switch]$Compact,
    [switch]$WarmUp,
    [switch]$All
)

$ErrorActionPreference = "Stop"

# --- Ollama Keep-Alive ---
if ($All -or $WarmUp) {
    Write-Host "`n[1/4] Configurando Ollama keep-alive..." -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "-1", "User")
    
    Write-Host "  Aquecendo modelo de embeddings..."
    $body = @{ model = "nomic-embed-text"; prompt = "warmup query for initialization" } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "http://localhost:11434/api/embeddings" -Method Post -Body $body -ContentType "application/json" | Out-Null
        Write-Host "  OK - Modelo carregado em memória" -ForegroundColor Green
    } catch {
        Write-Host "  AVISO - Ollama não está rodando. Inicie com 'ollama serve'" -ForegroundColor Yellow
    }
}

# --- LanceDB Indexes ---
if ($All -or $CreateIndexes) {
    Write-Host "`n[2/4] Criando índices no LanceDB..." -ForegroundColor Cyan
    python -c @"
import lancedb
import sys

db_path = r'$env:USERPROFILE\.copilot-rag\lancedb'
try:
    db = lancedb.connect(db_path)
    table = db.open_table('code_chunks')
    row_count = table.count_rows()
    print(f'  Tabela: {row_count} chunks')
    
    if row_count > 100000:
        print('  Criando indice vetorial IVF_PQ...')
        import math
        num_partitions = int(math.sqrt(row_count))
        table.create_index(
            metric='cosine',
            num_partitions=min(num_partitions, 512),
            num_sub_vectors=48,
            index_type='IVF_PQ',
            replace=True
        )
        print('  OK - Indice vetorial criado')
    else:
        print('  SKIP - Menos de 100K chunks, brute-force e suficiente')
    
    # Indices escalares
    print('  Criando indices escalares...')
    try:
        table.create_index('file_path', index_type='BTREE', replace=True)
        table.create_index('language', index_type='BITMAP', replace=True)
        print('  OK - Indices escalares criados')
    except Exception as e:
        print(f'  AVISO - {e}')

except FileNotFoundError:
    print('  SKIP - Banco nao encontrado. Execute index-workspace.ps1 primeiro.')
except Exception as e:
    print(f'  ERRO - {e}')
    sys.exit(1)
"@
}

# --- LanceDB Compaction ---
if ($All -or $Compact) {
    Write-Host "`n[3/4] Compactando LanceDB..." -ForegroundColor Cyan
    python -c @"
import lancedb
from datetime import timedelta

db_path = r'$env:USERPROFILE\.copilot-rag\lancedb'
try:
    db = lancedb.connect(db_path)
    table = db.open_table('code_chunks')
    table.optimize(cleanup_older_than=timedelta(days=7))
    print('  OK - Compactacao concluida')
except FileNotFoundError:
    print('  SKIP - Banco nao encontrado.')
except Exception as e:
    print(f'  AVISO - {e}')
"@
}

# --- Resumo ---
Write-Host "`n[4/4] Verificando estado final..." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ollama keep-alive: $([System.Environment]::GetEnvironmentVariable('OLLAMA_KEEP_ALIVE', 'User'))" 
Write-Host "  LanceDB path: $env:USERPROFILE\.copilot-rag\lancedb"
Write-Host ""
Write-Host "Otimizacao concluida!" -ForegroundColor Green
Write-Host ""
Write-Host "Proximos passos:" -ForegroundColor Yellow
Write-Host "  1. Reinicie o Ollama para aplicar keep-alive"
Write-Host "  2. Abra os projetos principais no IntelliJ (warm-up LSP)"
Write-Host "  3. Execute o health-check: .\scripts\health-check.ps1"
```

---

## Métricas de Referência (Benchmarks)

Os valores abaixo servem como referência para identificar degradação:

| Métrica | Aceitável | Atenção | Crítico |
| :--- | :--- | :--- | :--- |
| Embedding (warm) | <100ms | 100-500ms | >500ms |
| Busca vetorial (com índice) | <50ms | 50-200ms | >200ms |
| Busca vetorial (brute-force) | <500ms | 500ms-2s | >2s |
| Serena `find_symbol` (warm) | <300ms | 300ms-1s | >1s |
| Serena `activate_project` | <3s | 3-10s | >10s |
| Query completa (E2E) | <5s | 5-15s | >15s |
| Indexação incremental | <30s | 30s-2min | >2min |
| Indexação full (100K files) | <10min | 10-30min | >30min |

Use o **dashboard de monitoramento** (`scripts/generate-dashboard.ps1`) para rastrear essas métricas ao longo do tempo e identificar degradação.

---

## Checklist de Otimização

Execute periodicamente (recomendado: semanalmente):

- [ ] Ollama keep-alive configurado (`OLLAMA_KEEP_ALIVE=-1`)
- [ ] Modelo pré-aquecido após boot
- [ ] LanceDB com índice vetorial (se >100K chunks)
- [ ] LanceDB com índices escalares (file_path, language)
- [ ] LanceDB compactado (sem fragmentos excessivos)
- [ ] Indexação incremental configurada (não full a cada vez)
- [ ] Projetos principais abertos no IntelliJ (LSP warm)
- [ ] Dashboard de monitoramento verificado (sem gargalos >5s)
- [ ] Memória do Compozy compactada (max 4K tokens herdados)

---

## Referências

[1] CData Engineering. "Top 10 Proven MCP Performance Optimization Techniques for 2026." CData Blog, Fev. 2026.

[2] Ollama. "Embedding models." Ollama Blog, Abr. 2024. Disponível em: https://ollama.com/blog/embedding-models

[3] LanceDB. "Performance Tips and Best Practices." LanceDB Docs, 2026. Disponível em: https://docs.lancedb.com/performance

[4] Anthropic Engineering. "Code execution with MCP: Building more efficient agents." Anthropic Blog, Nov. 2025. Disponível em: https://www.anthropic.com/engineering/code-execution-with-mcp

[5] Martin Fowler. "Harness engineering for coding agent users." Thoughtworks, Abr. 2026.
