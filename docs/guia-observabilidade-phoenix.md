# Guia de Observabilidade — Arize Phoenix

## Visão Geral

O **Arize Phoenix** é uma plataforma open-source de observabilidade para aplicações de IA que permite visualizar, depurar e avaliar o comportamento dos agentes autônomos do GitHub Copilot. Nesta solução, o Phoenix recebe **traces** via OpenTelemetry (OTLP) do `mcp-proxy-logger.py`, que intercepta toda comunicação JSON-RPC entre o Copilot Agent Mode e os MCP servers.

A integração permite responder perguntas fundamentais sobre o comportamento dos agentes:

- Quais tools o agente chamou e em que ordem?
- Quanto tempo cada tool call levou?
- Quais chamadas falharam e por quê?
- Qual o padrão de uso ao longo do tempo?
- Existe algum gargalo de performance?

---

## Arquitetura da Observabilidade

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Copilot Agent Mode                      │
│                     (IntelliJ / VS Code / CLI)                       │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ JSON-RPC (stdio)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        mcp-proxy-logger.py                           │
│                                                                      │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐  │
│  │ Interceptação │───▶│  Log JSONL local  │    │  OTEL Exporter   │  │
│  │  JSON-RPC     │    │  (~/.copilot-     │    │  (BatchSpan      │  │
│  │              │    │   metrics/)       │    │   Processor)     │  │
│  └──────────────┘    └──────────────────┘    └────────┬─────────┘  │
└───────────────────────────────┬───────────────────────┼─────────────┘
                                │ stdio                  │ OTLP HTTP
                                ▼                        ▼
┌───────────────────────┐    ┌─────────────────────────────────────────┐
│   MCP Server Real     │    │           Arize Phoenix                  │
│  (code-navigation,    │    │                                          │
│   code-search,        │    │  ┌─────────┐  ┌──────────┐  ┌────────┐ │
│   issue-tracker)      │    │  │ Traces  │  │ Projects │  │ Evals  │ │
│                       │    │  │  Tree   │  │  View    │  │ Scores │ │
│                       │    │  └─────────┘  └──────────┘  └────────┘ │
└───────────────────────┘    │                                          │
                             │  UI: http://localhost:6006               │
                             └─────────────────────────────────────────┘
```

---

## Instalação

### Pré-requisitos

O Phoenix requer apenas **Python 3.9+** (já presente no ambiente se você executou outros scripts de setup). Não requer Docker, privilégios de administrador ou serviços externos.

### Comando de Instalação

```powershell
.\scripts\setup-phoenix.ps1
```

Para instalar e iniciar imediatamente:

```powershell
.\scripts\setup-phoenix.ps1 -Start -AirGapped
```

O parâmetro `-AirGapped` é recomendado para ambientes corporativos, pois desabilita o carregamento de recursos externos (Google Fonts, telemetria).

### Verificação

```powershell
.\scripts\setup-phoenix.ps1 -Status
```

Saída esperada:

```
[Phoenix] Verificando status do Phoenix...
[OK] Phoenix está rodando em http://localhost:6006
  OTEL HTTP: http://localhost:6006/v1/traces
  OTEL gRPC: localhost:4317
  Working Dir: C:\Users\rodrigo\.phoenix
[OK] Phoenix instalado: v5.x.x
```

---

## Configuração do Monitoramento MCP

Para que os traces dos agentes sejam enviados ao Phoenix, é necessário habilitar o modo `--phoenix` no proxy logger. Isso é feito no `mcp.json`:

### mcp.json com Monitoramento Phoenix

```json
{
  "servers": {
    "code-navigation": {
      "type": "stdio",
      "command": "python",
      "args": [
        "${userHome}/.copilot-metrics/mcp-proxy-logger.py",
        "--server", "code-navigation",
        "--command", "serena",
        "--args", "--context=jb-copilot-plugin",
        "--phoenix"
      ]
    },
    "code-search": {
      "type": "stdio",
      "command": "python",
      "args": [
        "${userHome}/.copilot-metrics/mcp-proxy-logger.py",
        "--server", "code-search",
        "--command", "codebase-memory-mcp",
        "--phoenix"
      ]
    },
    "issue-tracker": {
      "type": "stdio",
      "command": "python",
      "args": [
        "${userHome}/.copilot-metrics/mcp-proxy-logger.py",
        "--server", "issue-tracker",
        "--command", "atlassian-rovo-mcp",
        "--phoenix"
      ]
    }
  }
}
```

A flag `--phoenix` ativa a exportação OTEL. Sem ela, apenas o log JSONL local é gerado (comportamento padrão, sem overhead de rede).

---

## Variáveis de Ambiente

| Variável | Padrão | Descrição |
|:---|:---|:---|
| `PHOENIX_PORT` | `6006` | Porta HTTP (UI + OTEL collector) |
| `PHOENIX_GRPC_PORT` | `4317` | Porta gRPC para OTLP |
| `PHOENIX_WORKING_DIR` | `~/.phoenix` | Diretório de dados (SQLite) |
| `PHOENIX_COLLECTOR_ENDPOINT` | `http://localhost:6006` | Endpoint para envio de traces |
| `PHOENIX_PROJECT_NAME` | `copilot-agent-traces` | Projeto padrão no Phoenix |
| `PHOENIX_TELEMETRY_ENABLED` | `false` | Desabilita analytics da Arize |
| `PHOENIX_ALLOW_EXTERNAL_RESOURCES` | `false` | Modo air-gapped (sem fonts externas) |
| `PHOENIX_ALLOWED_PROVIDERS` | `OLLAMA` | Restringe playground ao Ollama local |

Todas são configuradas automaticamente pelo `setup-phoenix.ps1`.

---

## Exemplos de Traces

### Exemplo 1: Sessão de Desenvolvimento (code-navigation)

Quando o agente Copilot executa uma tarefa de refatoração, o trace capturado mostra a sequência de decisões:

```
Trace: mcp-session/code-navigation
├── code-navigation/find_symbol          [42ms]  ✓
│   input: {"symbol": "PaymentService", "kind": "class"}
│   output: {"file": "src/payment/service.ts", "line": 15}
│
├── code-navigation/get_references       [128ms] ✓
│   input: {"symbol": "PaymentService.process", "scope": "workspace"}
│   output: {"references": [...], "count": 7}
│
├── code-navigation/get_implementations  [85ms]  ✓
│   input: {"symbol": "IPaymentGateway"}
│   output: {"implementations": ["StripeGateway", "AdyenGateway"]}
│
├── code-navigation/apply_edit           [23ms]  ✓
│   input: {"file": "src/payment/service.ts", "edit": {...}}
│   output: {"applied": true}
│
└── code-navigation/rename_symbol        [156ms] ✓
    input: {"old": "process", "new": "processPayment"}
    output: {"files_modified": 4, "references_updated": 7}
```

**Insights extraídos:**
- O agente seguiu um padrão correto: localizar → verificar referências → verificar implementações → editar → renomear
- `get_references` foi a chamada mais lenta (128ms) — indica codebase grande
- Todas as chamadas foram bem-sucedidas (sem retries)

---

### Exemplo 2: Busca Semântica com Erro (code-search)

```
Trace: mcp-session/code-search
├── code-search/semantic_query           [312ms] ✓
│   input: {"query": "como funciona a autenticação JWT"}
│   output: {"results": [...], "count": 5}
│
├── code-search/get_architecture         [89ms]  ✓
│   input: {"scope": "auth"}
│   output: {"components": [...], "relationships": [...]}
│
├── code-search/trace_call_path          [1247ms] ✗ ERROR
│   input: {"from": "AuthController.login", "to": "TokenService.generate"}
│   error: "Symbol not found in index. Run 'codebase-memory-mcp index' first."
│
└── code-search/detect_changes           [45ms]  ✓
    input: {"since": "HEAD~5"}
    output: {"files_changed": 12, "symbols_affected": 34}
```

**Insights extraídos:**
- `trace_call_path` falhou porque o índice está desatualizado
- A busca semântica funcionou (312ms — aceitável para embedding local)
- **Ação recomendada:** Executar `.\scripts\index-workspace.ps1` para re-indexar

---

### Exemplo 3: Leitura de Issue (issue-tracker)

```
Trace: mcp-session/issue-tracker
├── issue-tracker/get_issue              [890ms] ✓
│   input: {"key": "SQUAD-100"}
│   output: {"type": "Epic", "summary": "Gestão de Recorrências...", ...}
│
├── issue-tracker/search_issues          [1456ms] ✓
│   input: {"jql": "parent = SQUAD-100 ORDER BY rank"}
│   output: {"issues": [...], "total": 6}
│
├── issue-tracker/get_issue              [723ms] ✓
│   input: {"key": "SQUAD-101"}
│   output: {"type": "Story", "summary": "Cadastro de plano...", ...}
│
├── issue-tracker/get_issue              [698ms] ✓
│   input: {"key": "SQUAD-102"}
│   output: {"type": "Story", ...}
│
├── issue-tracker/get_comments           [534ms] ✓
│   input: {"key": "SQUAD-100", "maxResults": 20}
│   output: {"comments": [...], "total": 8}
│
└── issue-tracker/get_issue_links        [412ms] ✓
    input: {"key": "SQUAD-100"}
    output: {"links": [...], "total": 3}
```

**Insights extraídos:**
- Latência alta nas chamadas ao Jira (890ms–1456ms) — esperado para API remota
- O agente seguiu o padrão correto do `analista-sistemas.agent.md`: épico → histórias filhas → comentários → links
- Total de 6 chamadas para coletar contexto completo (~4.7s total)

---

## Recursos Principais do Phoenix

### 1. Trace Tree (Árvore de Traces)

A visualização principal do Phoenix. Mostra cada sessão como uma árvore hierárquica de spans, permitindo:

- Visualizar a sequência exata de tool calls
- Identificar chamadas lentas (barras coloridas por duração)
- Expandir cada span para ver input/output completo
- Filtrar por status (sucesso/erro)

**Acesso:** `http://localhost:6006` → aba "Traces"

### 2. Projects (Projetos)

Agrupa traces por contexto. Na nossa configuração, cada MCP server gera um projeto separado:

| Projeto | Conteúdo |
|:---|:---|
| `copilot-agent-traces` | Projeto padrão (todos os servers) |
| `mcp-code-navigation` | Apenas traces do code-navigation |
| `mcp-code-search` | Apenas traces do code-search |
| `mcp-issue-tracker` | Apenas traces do issue-tracker |

Para separar por projeto, use `--phoenix-project` no proxy logger:

```json
"args": ["--phoenix", "--phoenix-project", "mcp-code-navigation"]
```

### 3. Span Attributes (Atributos dos Spans)

Cada span exportado contém atributos estruturados seguindo as convenções **OpenInference**:

| Atributo | Descrição | Exemplo |
|:---|:---|:---|
| `mcp.server` | Nome lógico do server | `code-navigation` |
| `mcp.method` | Método JSON-RPC | `tools/call` |
| `mcp.tool` | Nome da tool chamada | `find_symbol` |
| `mcp.params` | Parâmetros (resumo) | `{"symbol": "PaymentService"}` |
| `mcp.duration_ms` | Duração em ms | `42.5` |
| `mcp.success` | Sucesso/falha | `true` |
| `mcp.error` | Mensagem de erro | `Symbol not found` |
| `openinference.span.kind` | Tipo OpenInference | `TOOL` |
| `input.value` | Input da tool | JSON dos params |
| `output.value` | Output da tool | JSON do resultado |

### 4. Filtering e Search

O Phoenix permite filtrar traces por:

- **Tempo:** Últimos 5min, 1h, 24h, 7d, ou range customizado
- **Status:** Sucesso, Erro, ou ambos
- **Latência:** Acima de X ms (útil para encontrar gargalos)
- **Atributos:** Qualquer atributo do span (ex: `mcp.tool = "semantic_query"`)
- **Texto livre:** Busca em inputs/outputs

### 5. Métricas Agregadas

O Phoenix calcula automaticamente:

- **Throughput:** Chamadas por minuto/hora
- **Latência P50/P95/P99:** Distribuição de tempos de resposta
- **Error Rate:** Porcentagem de falhas por server/tool
- **Token Usage:** Se integrado com LLM provider (futuro)

### 6. Evaluations (Avaliações)

Recurso avançado para medir qualidade das respostas dos agentes. Permite definir critérios de avaliação e aplicar scores automáticos aos traces. Útil para:

- Medir se o agente está seguindo o fluxo correto
- Comparar performance antes/depois de mudanças nos prompts
- Identificar regressões em novas versões dos MCP servers

---

## Logs JSONL (Modo Offline)

Independentemente do Phoenix, o proxy logger **sempre** gera logs em `~/.copilot-metrics/calls.jsonl`. Este formato é útil para:

- Análise offline (sem Phoenix rodando)
- Scripts de relatório customizados
- Auditoria de uso

### Formato do JSONL

```json
{
  "timestamp": "2026-06-26T14:32:15.123456+00:00",
  "server": "code-navigation",
  "method": "tools/call",
  "tool": "find_symbol",
  "params_summary": "{\"symbol\": \"PaymentService\", \"kind\": \"class\"}",
  "duration_ms": 42.31,
  "success": true,
  "error": null
}
```

### Consultas Úteis com PowerShell

```powershell
# Top 10 tools mais usadas
Get-Content ~/.copilot-metrics/calls.jsonl |
  ConvertFrom-Json |
  Group-Object tool |
  Sort-Object Count -Descending |
  Select-Object -First 10 Name, Count

# Chamadas com erro nas últimas 24h
Get-Content ~/.copilot-metrics/calls.jsonl |
  ConvertFrom-Json |
  Where-Object { -not $_.success -and $_.timestamp -gt (Get-Date).AddDays(-1).ToString("o") }

# Latência média por server
Get-Content ~/.copilot-metrics/calls.jsonl |
  ConvertFrom-Json |
  Group-Object server |
  ForEach-Object {
    [PSCustomObject]@{
      Server = $_.Name
      AvgMs = [math]::Round(($_.Group | Measure-Object duration_ms -Average).Average, 1)
      Count = $_.Count
    }
  }
```

---

## Operações do Servidor

| Operação | Comando |
|:---|:---|
| Instalar | `.\scripts\setup-phoenix.ps1` |
| Iniciar | `.\scripts\setup-phoenix.ps1 -Start` |
| Parar | `.\scripts\setup-phoenix.ps1 -Stop` |
| Status | `.\scripts\setup-phoenix.ps1 -Status` |
| Atualizar | `.\scripts\setup-phoenix.ps1 -Upgrade` |
| Início rápido (bat) | `%USERPROFILE%\.phoenix\start-phoenix.bat` |

---

## Troubleshooting

| Sintoma | Causa Provável | Solução |
|:---|:---|:---|
| Phoenix não inicia | Porta 6006 em uso | `.\scripts\setup-phoenix.ps1 -Start -Port 9090` |
| Traces não aparecem | Proxy sem `--phoenix` | Verificar `mcp.json` inclui flag `--phoenix` |
| "OTEL não disponível" | Pacotes não instalados | Re-executar `.\scripts\setup-phoenix.ps1` |
| UI lenta ao carregar | Recursos externos bloqueados | Usar `-AirGapped` no setup |
| Spans sem output | Resposta muito grande | Normal — output é truncado em 500 chars |
| Muitos traces antigos | Sem retention policy | Definir `PHOENIX_DEFAULT_RETENTION_POLICY_DAYS=30` |

---

## Referências

- [Arize Phoenix — Documentação Oficial](https://arize.com/docs/phoenix)
- [OpenTelemetry — Especificação OTLP](https://opentelemetry.io/docs/specs/otlp/)
- [OpenInference — Semantic Conventions](https://github.com/Arize-ai/openinference)
- [Phoenix GitHub](https://github.com/Arize-ai/phoenix)
