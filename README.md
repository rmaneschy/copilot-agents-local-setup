# Copilot Agents Local Setup

## Visão Geral do Projeto

O projeto **Copilot Agents Local Setup** fornece os scripts, configurações e ferramentas necessários para provisionar um ambiente de **code intelligence** 100% local, voltado para a análise avançada de código-fonte por agentes autônomos. A solução foi concebida para operar em ambientes de desenvolvimento corporativos restritos — tanto em **Windows 11** quanto em **Linux** — onde o usuário não possui privilégios de administrador e não há disponibilidade de contêineres Docker.

A integração principal ocorre com o **IntelliJ IDEA** (e opcionalmente VS Code) através do plugin **GitHub Copilot Chat**, utilizando o padrão *Model Context Protocol* (MCP). A solução combina **duas abordagens complementares**: knowledge graph com busca semântica integrada (codebase-memory-mcp) e navegação estrutural determinística (Serena MCP via LSP).

> **Nota:** Os documentos conceituais sobre agentes, orquestradores e melhores práticas estão no repositório irmão [copilot-agents-setup](https://github.com/rmaneschy/copilot-agents-setup). Este repositório foca na **infraestrutura local** (instalação, configuração e operação).

---

## Pré-requisitos

| Requisito | Windows | Linux |
|:---|:---|:---|
| **Python 3.10–3.13** | Instalado via Microsoft Store ou `winget` (recomendado: 3.12 para melhor compatibilidade de wheels) | `python3` (pré-instalado na maioria das distros) |
| **Git** | Git for Windows | `git` (pré-instalado) |
| **IntelliJ IDEA** | Com plugin GitHub Copilot | Com plugin GitHub Copilot |
| **Internet** | Apenas na primeira execução | Apenas na primeira execução |
| **Admin/sudo** | ❌ Não necessário | ❌ Não necessário |
| **Docker** | ❌ Não necessário | ❌ Não necessário |
| **go-task** | Binário único (~5MB), sem admin: `task install-task` | `sh -c "$(curl -fsSL https://taskfile.dev/install.sh)" -- -d ~/.local/bin` |
| **jq** (opcional) | `winget install jqlang.jq` | `apt install jq` ou já disponível |

---

## Taskfile — Orquestrador Unificado

O **Taskfile.yml** ([go-task](https://taskfile.dev)) é o ponto de entrada único para todas as operações. É um binário único (~5MB) que não requer instalação de toolchain, funciona em Windows/Linux/macOS e detecta automaticamente o sistema operacional para executar o script correto (`.ps1` no Windows, `.sh` no Linux).

**Instalação do go-task (sem admin):**

```powershell
# Windows (PowerShell)
Invoke-WebRequest -Uri "https://github.com/go-task/task/releases/latest/download/task_windows_amd64.zip" -OutFile "$env:TEMP\task.zip"
Expand-Archive "$env:TEMP\task.zip" -DestinationPath "$env:USERPROFILE\.local\bin" -Force
# Adicionar ao PATH: $env:PATH += ";$env:USERPROFILE\.local\bin"
```

```bash
# Linux
sh -c "$(curl -fsSL https://taskfile.dev/install.sh)" -- -d ~/.local/bin
```

**Comandos disponíveis:**

```bash
# Ver todos os comandos disponíveis
task --list

# Instalação completa (todos os componentes)
task install

# Setup completo (install + index)
task setup

# Instalar componentes individualmente
task install-code-search       # codebase-memory-mcp
task install-code-navigation   # Serena MCP
task install-observability     # Arize Phoenix

# Indexar workspace
task index

# Indexar repositório específico
task index-repo -- nome-do-repo

# Verificar saúde do ambiente
task check

# Iniciar/parar/status Phoenix
task start-phoenix
task stop-phoenix
task status-phoenix

# Atualizar todos os componentes
task upgrade

# Alternar modo online/offline
task mode-online
task mode-offline

# Limpar caches (requer re-indexação)
task clean
```

---

## Fluxo de Execução — Cenário Principal (Máquina Limpa)

Este é o passo a passo completo para configurar uma máquina nova do zero. Siga **na ordem indicada**.

### Fase 1: Instalação dos Componentes

| Passo | Comando | Tempo | Descrição |
|:---:|:---|:---:|:---|
| 1 | `task install-code-search` | ~2 min | Verifica versão local vs remota (skip se já atualizado), baixa binário estático (~15MB), instala no PATH do usuário, configura `mcp.json` |
| 2 | `task install-code-navigation` | ~3 min | Instala `uv` + Serena MCP (LSP server) sem admin |
| 3 | `task install-observability` | ~3 min | Instala Arize Phoenix (observabilidade) e inicia o servidor local |
| 4 | `task index` | ~5 min* | Descobre repos via `.git` e indexa o knowledge graph (*varia com tamanho do workspace) |

**Total estimado:** ~13 minutos (primeira execução com internet).

**Atalho:** Para executar todos os passos de uma vez:

```bash
task setup
```

**Equivalente sem Taskfile (execução direta):**

| OS | Comando |
|:---|:---|
| **Windows** (PowerShell) | `.\scripts\setup-codebase-memory.ps1` → `.\scripts\setup-serena.ps1` → `.\scripts\setup-phoenix.ps1 -Start -AirGapped` → `.\scripts\index-workspace.ps1` |
| **Linux** (Bash) | `./scripts/setup-codebase-memory.sh` → `./scripts/setup-serena.sh` → `./scripts/setup-phoenix.sh --start --air-gapped` → `./scripts/index-workspace.sh` |

### Fase 2: Configuração do IntelliJ IDEA

Após a Fase 1, configure o IntelliJ para reconhecer os servidores MCP:

| Passo | Ação | Caminho no IntelliJ |
|:---:|:---|:---|
| 5 | Abrir Settings | `File → Settings` (ou `Ctrl+Alt+S`) |
| 6 | Navegar até MCP | `Tools → GitHub Copilot → Model Context Protocol (MCP)` |
| 7 | Clicar em "Configure" | Abre o arquivo `mcp.json` para edição |
| 8 | Colar configuração | Copiar o conteúdo de `.vscode/mcp.json` deste repositório |
| 9 | Salvar e fechar | O IntelliJ detecta automaticamente os novos servers |
| 10 | Reiniciar o IntelliJ | Necessário para carregar os MCP servers |

**Conteúdo do `mcp.json` (padrão sem monitoramento):**

```json
{
  "servers": {
    "code-navigation": {
      "type": "stdio",
      "command": "serena",
      "args": ["--context=jb-copilot-plugin"]
    },
    "code-search": {
      "type": "stdio",
      "command": "codebase-memory-mcp",
      "args": []
    }
  }
}
```

**Conteúdo do `mcp.json` (com monitoramento Phoenix):**

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
    }
  }
}
```

> **Linux:** No Linux, substitua `python` por `python3` nos comandos do `mcp.json` com monitoramento, caso `python` não esteja no PATH.

### Fase 3: Validação no IntelliJ

Após reiniciar o IntelliJ, valide que tudo está funcionando:

| Passo | Ação | Resultado Esperado |
|:---:|:---|:---|
| 11 | Abrir Copilot Chat | Painel lateral com ícone do Copilot |
| 12 | Verificar tools disponíveis | Clicar no ícone de ferramentas (🔧) no chat — deve listar `code-navigation` e `code-search` |
| 13 | Testar `code-search` | Digitar: *"Busque funções relacionadas a autenticação neste projeto"* |
| 14 | Testar `code-navigation` | Digitar: *"Encontre todas as referências ao símbolo PaymentService"* |
| 15 | Verificar Agent Mode | Digitar `/agent` ou selecionar modo "Agent" no dropdown — deve mostrar tools MCP disponíveis |

**Sinais de que está funcionando:**
- O Copilot menciona "Using tool: code-search" ou "Using tool: code-navigation" nas respostas
- Os resultados contêm referências a arquivos reais do seu projeto
- Não há mensagens de erro "MCP server not found" ou "Connection refused"

**Validação via terminal (alternativa):**

```bash
# Verificar saúde de todos os componentes
task check

# Saída esperada:
#   ✓ codebase-memory-mcp — Binário encontrado (v1.x.x)
#   ✓ Serena MCP — Binário encontrado
#   ✓ Phoenix — Instalado e rodando (PID xxxx)
#   ✓ mcp.json — Configuração válida
```

**Troubleshooting rápido:**

| Sintoma | Solução |
|:---|:---|
| Tools não aparecem no chat | Reiniciar IntelliJ; verificar se `mcp.json` está em `Tools > GitHub Copilot > MCP` |
| "Server not found" | Executar `task check` para verificar binários no PATH |
| "Connection refused" | **Windows:** `where.exe codebase-memory-mcp` / **Linux:** `which codebase-memory-mcp` |
| Tools aparecem mas não retornam resultados | Executar `task index` para indexar o workspace |
| Phoenix não recebe traces | Verificar se o `mcp.json` usa a versão com `--phoenix` e se Phoenix está rodando (`task status-phoenix`) |
| `pip install` falha com `subprocess-exited-with-error` | Python 3.14+ pode não ter wheels pré-compiladas. Instale Python 3.12: `winget install Python.Python.3.12`. O script usará automaticamente via `py -3.12`. |
| Serena: `projects key not found in Serena configuration` | O `serena_config.yml` não possui a chave `projects` (obrigatória desde Serena 1.1+). Re-execute `task install-serena` para corrigir automaticamente, ou adicione manualmente ao final do `~/.serena/serena_config.yml`: `projects:\n  - ~/workspace` |

---

## Fluxos Alternativos

### Cenário A: Máquina já configurada (uso diário)

Nenhum script é necessário no dia a dia. Os servidores MCP são invocados automaticamente pelo IntelliJ quando o Copilot precisa de uma tool. O knowledge graph é atualizado automaticamente via git-based change detection.

Se desejar iniciar o Phoenix para monitoramento:

```bash
task start-phoenix
```

### Cenário B: Novo repositório adicionado ao workspace

```bash
# Via Taskfile (detecta OS automaticamente)
task index-repo -- nome-do-novo-repo

# Ou diretamente:
# Windows: .\scripts\index-workspace.ps1 -Include "nome-do-novo-repo"
# Linux:   ./scripts/index-workspace.sh --include "nome-do-novo-repo"
```

### Cenário C: Atualização dos componentes

Os scripts de instalação possuem **detecção inteligente de versão**: antes de baixar qualquer binário, consultam a versão mais recente disponível via GitHub API e comparam com a versão local instalada. Se já estiver na versão mais recente, o download é automaticamente ignorado (*skip*). Caso não haja conexão com a internet, a versão atual é mantida sem erro.

```bash
# Via Taskfile (detecta OS automaticamente)
task upgrade
```

Ou individualmente:

| Componente | Windows | Linux |
|:---|:---|:---|
| codebase-memory-mcp | `.\scripts\setup-codebase-memory.ps1 -Upgrade` | `./scripts/setup-codebase-memory.sh --upgrade` |
| Serena MCP | `.\scripts\setup-serena.ps1 -Upgrade` | `./scripts/setup-serena.sh --upgrade` |
| Phoenix | `.\scripts\setup-phoenix.ps1 -Upgrade` | `./scripts/setup-phoenix.sh --force-reinstall` |

### Cenário D: Habilitar monitoramento após instalação inicial

```bash
# Instalar Phoenix (se não fez na Fase 1)
task install-observability

# Iniciar Phoenix
task start-phoenix

# Habilitar proxy logger com export OTEL (Windows)
.\scripts\toggle-monitoring.ps1 -Enable -Phoenix

# Reiniciar IntelliJ para aplicar novo mcp.json
```

### Cenário E: Ambiente com proxy corporativo (SSL inspection)

```bash
# Executar antes dos demais scripts (apenas Windows)
.\scripts\setup-proxy-workaround.ps1

# Depois seguir o fluxo principal normalmente
task install
```

### Cenário F: Compartilhar índice com o time (evitar re-indexação)

```bash
# Desenvolvedor que indexou primeiro:
git add .codebase-memory/graph.db.zst
git commit -m "chore: atualiza índice do knowledge graph"
git push

# Colegas do time:
git pull  # índice atualizado automaticamente (incremental)
```

---

## Slider Online/Offline: GitHub Copilot ↔ Ollama

A solução suporta dois modos de operação do LLM (modelo de linguagem que gera as respostas). Os **servidores MCP** (code-search, code-navigation) funcionam **independentemente** do modo escolhido — eles apenas fornecem contexto; quem "pensa" é o LLM.

### Modo Online (Padrão): GitHub Copilot Cloud

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Desenvolvedor  │────▶│  GitHub Copilot   │────▶│  GPT-4o / Claude /  │
│  (IntelliJ)     │     │  Plugin           │     │  Gemini (Cloud)     │
└─────────────────┘     └────────┬─────────┘     └─────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
              code-search  code-navigation  issue-tracker
              (local MCP)   (local MCP)     (local MCP)
```

**Configuração:** Nenhuma alteração necessária. O plugin do GitHub Copilot usa os modelos cloud por padrão.

**Seleção de modelo no IntelliJ:**
1. Abrir Copilot Chat
2. No rodapé do chat, clicar no dropdown do modelo atual (ex: "GPT-4o")
3. Selecionar o modelo desejado (GPT-4o, Claude Sonnet, Gemini, etc.)

**Vantagens:** Modelos maiores e mais capazes, zero consumo de GPU local, sempre atualizado.

**Quando usar:** Tarefas complexas (arquitetura, refatoração grande, análise cross-service), quando há internet disponível.

---

### Modo Offline: Ollama Local

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Desenvolvedor  │────▶│  GitHub Copilot   │────▶│  Ollama             │
│  (IntelliJ)     │     │  Plugin (BYOK)    │     │  (localhost:11434)  │
└─────────────────┘     └────────┬─────────┘     └─────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
              code-search  code-navigation  issue-tracker
              (local MCP)   (local MCP)     (local MCP)
```

**Pré-requisitos:**
1. Ollama instalado e rodando (`ollama serve`)
2. Modelo com suporte a **tool calling** baixado (ex: `qwen2.5-coder:32b`, `llama3.1:70b`)

**Configuração no IntelliJ (JetBrains AI Assistant):**

| Passo | Ação | Caminho |
|:---:|:---|:---|
| 1 | Abrir Settings | `File → Settings → Tools → AI Assistant → Providers & API Keys` |
| 2 | Adicionar provider | Selecionar "Ollama" na lista de providers |
| 3 | Configurar URL | `http://localhost:11434` |
| 4 | Testar conexão | Clicar "Test Connection" — deve retornar sucesso |
| 5 | Atribuir modelo | Em "Model Assignment" → "Core features" → selecionar o modelo Ollama |
| 6 | Aplicar | Clicar OK e reiniciar o chat |

**Configuração via Copilot CLI (Terminal):**

```bash
# Variáveis de ambiente para modo offline completo
export COPILOT_PROVIDER_BASE_URL="http://localhost:11434"
export COPILOT_MODEL="qwen2.5-coder:32b"
export COPILOT_OFFLINE="true"

# Iniciar Copilot CLI em modo offline
copilot
```

**Vantagens:** 100% offline, privacidade total, sem custo por token, sem dependência de internet.

**Quando usar:** Ambientes air-gapped, código sensível/NDA, quando internet está indisponível, experimentação sem consumir créditos.

---

### Como Alternar entre Online e Offline

A alternância é feita **no nível do modelo selecionado**, não nos servidores MCP:

| Ação | Online → Offline | Offline → Online |
|:---|:---|:---|
| **Via Taskfile** | `task mode-offline` | `task mode-online` |
| **IntelliJ (AI Assistant)** | Settings → AI Assistant → Model Assignment → selecionar modelo Ollama | Settings → AI Assistant → Model Assignment → selecionar modelo cloud |
| **IntelliJ (Copilot Chat)** | Dropdown do modelo no chat → selecionar modelo local (se configurado via BYOK) | Dropdown do modelo no chat → selecionar GPT-4o/Claude/Gemini |
| **Copilot CLI** | Definir `COPILOT_PROVIDER_BASE_URL` + `COPILOT_OFFLINE=true` | Remover variáveis de ambiente (usa cloud por padrão) |

> **Importante:** Os servidores MCP (code-search, code-navigation) **não precisam ser reconfigurados** ao alternar. Eles são agnósticos ao LLM — funcionam igualmente em ambos os modos.

### Modelos Recomendados para Modo Offline

| Modelo | RAM Mínima | Tool Calling | Contexto | Recomendação |
|:---|:---:|:---:|:---:|:---|
| `qwen2.5-coder:7b` | 8 GB | ✓ | 128k | Mínimo viável para Agent Mode |
| `qwen2.5-coder:32b` | 24 GB | ✓ | 128k | Melhor custo-benefício para desenvolvimento |
| `llama3.1:70b` | 48 GB | ✓ | 128k | Mais capaz, requer GPU dedicada |
| `deepseek-coder-v2:16b` | 12 GB | ✓ | 128k | Boa alternativa para hardware limitado |

Para configurar o Ollama com tweaks de performance:

```bash
# Baixar modelo recomendado
ollama pull qwen2.5-coder:32b

# Aplicar tweaks de performance (Windows)
.\scripts\apply-ollama-tweaks.ps1
```

---

## Arquitetura e Componentes da Solução

A arquitetura baseia-se na composição de ferramentas de código aberto e leves, garantindo privacidade absoluta (o código nunca sai da máquina para ser indexado) e baixo consumo de recursos do desenvolvedor.

| Componente | Função | Justificativa |
|:---|:---|:---|
| **codebase-memory-mcp** | Motor de code intelligence que indexa o código em um knowledge graph persistente, expondo 14 ferramentas MCP (busca semântica, call graph, análise de impacto, arquitetura). | Binário estático único (C puro), zero dependências. Modelo de embedding (`nomic-embed-code`, 768d) compilado no binário. 158 linguagens via tree-sitter. 100% offline desde o primeiro uso. |
| **Serena MCP** | Servidor MCP patrocinado pela Microsoft que utiliza o *Language Server Protocol* (LSP). | Fornece navegação determinística no código (find_symbol, find_references), complementando o knowledge graph. Instala-se via `uv` sem privilégios de administrador. |
| **Arize Phoenix** | Plataforma open-source de observabilidade para agentes de IA. | Visualiza traces de decisões dos agentes (tool calls, latência, erros). Instalação via pip, sem Docker. UI em `localhost:6006`. |
| **Ollama** (opcional) | Motor local para modelos de linguagem (chat/completion). | Permite instalação em nível de usuário no Windows (sem admin). Utilizado para LLM local no modo offline. |

Para um aprofundamento técnico, consulte o documento de [Arquitetura da Solução](docs/architecture.md) e a [Análise Comparativa com Alternativas de Mercado](docs/comparativo-alternativas.md).

---

## Estrutura do Repositório

```text
Taskfile.yml                             # Orquestrador unificado (go-task, detecta OS, chama .ps1 ou .sh)
.gitattributes                           # Controle de line endings (CRLF para .ps1, LF para .sh/.yml/.md)

.github/
├── agents/                              # Agentes especializados para uso com MCP
│   ├── techlead-architecture.md         #   Análise arquitetural de microserviços
│   ├── techlead-c4-diagram.md           #   Geração de diagramas C4 Container
│   ├── techlead-communication.md        #   Mapeamento de comunicação entre serviços
│   └── techlead-data-contracts.md       #   Contratos de dados, auth e dependências
├── prompts/                             # Prompts prontos para uso no Copilot Chat
│   ├── analyze-service.prompt.md        #   Análise de fluxo de ponta a ponta
│   ├── map-communication.prompt.md      #   Mapear dependências entre serviços
│   ├── query-authentication.prompt.md   #   Consultar autenticação/autorização
│   ├── query-database-access.prompt.md  #   Consultar acessos a banco de dados
│   └── query-openapi-dependencies.prompt.md # Consultar dependências de contratos
└── copilot-instructions.md              # Instruções de contexto global

.vscode/
├── mcp.json                             # Configuração MCP padrão
└── mcp-with-monitoring.json             # Configuração MCP com proxy de monitoramento

scripts/                                 # Automação de Setup
├── setup-codebase-memory.ps1            # [Windows] Setup codebase-memory-mcp
├── setup-codebase-memory.sh             # [Linux]   Setup codebase-memory-mcp
├── setup-serena.ps1                     # [Windows] Setup Serena MCP (uv + LSP)
├── setup-serena.sh                      # [Linux]   Setup Serena MCP (uv + LSP)
├── setup-phoenix.ps1                    # [Windows] Setup Arize Phoenix
├── setup-phoenix.sh                     # [Linux]   Setup Arize Phoenix
├── index-workspace.ps1                  # [Windows] Indexação recursiva (descobre repos via .git)
├── index-workspace.sh                   # [Linux]   Indexação recursiva (descobre repos via .git)
├── health-check.ps1                     # [Windows] Verificação de saúde dos componentes
├── health-check.sh                      # [Linux]   Verificação de saúde dos componentes
├── inspect-mcp.ps1                      # Verificação rápida de servidores MCP
├── toggle-monitoring.ps1                # Habilitar/desabilitar monitoramento MCP
├── generate-dashboard.ps1               # Gerar dashboard HTML de desempenho
├── optimize-environment.ps1             # Otimização de desempenho (keep-alive, índices)
├── apply-ollama-tweaks.ps1              # Aplica/troca tweaks do Ollama por perfil de hardware
├── setup-mcp-inspector.ps1              # Executa MCP Inspector (debug visual de tools)
├── setup-n8n.ps1                        # Setup n8n (orquestrador visual de agentes)
├── setup-proxy-workaround.ps1           # Contorno para proxy corporativo com SSL
└── legacy/                              # Scripts obsoletos (mantidos para referência)
    ├── README.md                        #   Documentação dos scripts legados
    ├── setup.ps1                        #   [LEGADO] Setup v1 (Ollama + mcp-vector-search)
    ├── setup-vector-search.ps1          #   [LEGADO] Setup mcp-vector-search v4
    └── setup-alternative-node.ps1       #   [LEGADO] Setup alternativo via Node.js/Bun

monitoring/
└── mcp-proxy-logger.py                  # Proxy transparente para logging JSON-RPC + export OTEL

docs/                                    # Documentação técnica da infraestrutura
├── architecture.md                      # Arquitetura detalhada da solução
├── comparativo-alternativas.md          # Comparação com Sourcebot, Continue.dev, Greptile
├── guia-observabilidade-phoenix.md      # Guia completo do Arize Phoenix (traces, logs, recursos)
├── guia-configuracao-mcp-aliases.md     # Como configurar mcp.json com tool aliases
├── analise-compatibilidade-linux.md     # Análise de portabilidade Windows → Linux
├── ollama-tweaks-e-perfis-hardware.md   # Tweaks do Ollama, KV Cache e perfis de hardware
├── diagrams/                            # Diagramas de arquitetura (D2 + PNG)
└── concepts/
    └── spec-driven-development-frameworks.md  # Comparativo SDD (SpecKit, Superpowers, OpenSpec)
```

---

## Ferramentas MCP Disponíveis (14 tools)

O codebase-memory-mcp expõe 14 ferramentas via MCP que o GitHub Copilot pode invocar automaticamente no Agent Mode:

| Ferramenta | Função |
|:---|:---|
| `search_graph` | Busca estrutural (regex, label, degree, file scoping) |
| `semantic_query` | Busca semântica vetorial em linguagem natural |
| `trace_call_path` | Call graph (quem chama / é chamado por) |
| `get_architecture` | Visão geral da arquitetura (linguagens, pacotes, entry points, rotas, hotspots) |
| `detect_changes` | Impacto de mudanças (git diff → símbolos afetados com classificação de risco) |
| `query_graph` | Queries Cypher-like no knowledge graph |
| `search_code` | Grep inteligente (graph-augmented, apenas em arquivos indexados) |
| `get_code_snippet` | Extrai trecho de código por símbolo |
| `manage_adr` | Architecture Decision Records (CRUD persistente entre sessões) |
| `ingest_traces` | Importar traces de execução |
| `dead_code` | Detecta funções com zero chamadores (excluindo entry points) |
| `cross_service` | Descobre comunicação HTTP/gRPC/GraphQL entre serviços |
| `similar_code` | Detecta near-clones via MinHash + LSH (Jaccard scored) |
| `community_detect` | Detecta módulos funcionais via Louvain clustering |

---

## Monitoramento e Observabilidade

O projeto inclui ferramentas completas para monitorar a saúde do sistema, o desempenho dos agentes e o fluxo de decisões via traces.

### Arize Phoenix (Observabilidade de Agentes)

O **Arize Phoenix** é a plataforma open-source de observabilidade que permite visualizar o fluxo completo de decisões dos agentes — quais tools foram chamadas, em que ordem, quanto tempo levaram e se houve erros. Funciona 100% local via `pip install`, sem Docker ou admin.

```bash
# Instalar e iniciar (modo air-gapped para corporativo)
task install-observability
task start-phoenix

# Verificar status
task status-phoenix

# Parar
task stop-phoenix
```

Acesse a UI em `http://localhost:6006` para visualizar traces em árvore, filtrar por latência/erro e analisar padrões de uso. Para detalhes completos, consulte o **[Guia de Observabilidade Phoenix](docs/guia-observabilidade-phoenix.md)**.

### Verificação de Saúde (Health Check)

```bash
task check
```

### Dashboard de Desempenho

```bash
# Habilitar monitoramento com Phoenix
task enable-monitoring

# Gerar dashboard HTML (Windows)
.\scripts\generate-dashboard.ps1

# Linux: abrir Phoenix UI diretamente em http://localhost:6006
```

---

## Ferramentas Visuais (MCP Inspector e n8n)

### MCP Inspector (Debug Visual de Servidores)

```bash
# Windows
.\scripts\setup-mcp-inspector.ps1
.\scripts\setup-mcp-inspector.ps1 -Server serena

# Linux
task inspect
```

A interface estará disponível em `http://localhost:6274`.

### n8n (Orquestrador Visual de Agentes)

```bash
# Windows
.\scripts\setup-n8n.ps1 -Start

# Linux (requer Node.js)
npx n8n start
```

A interface estará disponível em `http://localhost:5678`.

---

## Repositório Irmão

| Repositório | Propósito |
|:---|:---|
| [copilot-agents-setup](https://github.com/rmaneschy/copilot-agents-setup) | Estrutura de agentes, skills, instruções, prompts e diretrizes para o agente autônomo de desenvolvimento. |
| **Este repositório** | Scripts, configs e ferramentas para instalar e operar a infraestrutura local (codebase-memory-mcp, Serena, Phoenix, Ollama). |

---

## Contribuições e Padrões

Este projeto segue rigorosamente os princípios SOLID, código limpo e responsabilidade única. A arquitetura foi desenhada para ser aberta à expansão (adição de novos agentes e parsers) e fechada para alteração estrutural.

Todas as implementações devem ser acompanhadas de atualizações neste `README.md`. Os *commits* devem obrigatoriamente seguir o formato *Conventional Commits* (ex: `feat: adiciona script de health check`, `docs: melhora documentação arquitetural`). Certifique-se de que o código submetido seja funcional e esteja livre de erros de sintaxe.
