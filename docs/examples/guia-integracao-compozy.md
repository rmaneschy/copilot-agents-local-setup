# Guia de Integração: Compozy + RAG + Serena MCP

## Introdução

Este guia prático detalha como integrar o **Compozy** (orquestrador de ciclo de vida de desenvolvimento) com a infraestrutura de inteligência de código local que já configuramos neste projeto (RAG Vetorial + Serena MCP). 

A união dessas três ferramentas cria uma **esteira de desenvolvimento autônoma completa**:
1. **Compozy**: Orquestra o fluxo (Idea → PRD → TechSpec → Tasks) e fornece memória de longo prazo.
2. **RAG Vetorial**: Fornece busca semântica em todo o *workspace* para enriquecer as tarefas com contexto real do projeto.
3. **Serena MCP**: Fornece navegação determinística no código via *Language Server Protocol* (LSP) para execução precisa.

---

## Arquitetura da Integração

O Compozy utiliza o conceito de *Reusable Agents* (Agentes Reutilizáveis). Um agente no Compozy é definido por um diretório contendo um arquivo `AGENT.md` (o *prompt* e metadados) e um arquivo `mcp.json` opcional.

Quando o Compozy executa um agente (via `compozy exec` ou no fluxo de *tasks*), ele **injeta automaticamente os servidores MCP locais** definidos no `mcp.json` na sessão do protocolo ACP (*Agent Communication Protocol*). Isso significa que qualquer agente executor (como Copilot CLI, Claude Code ou Cursor) ganha acesso imediato às ferramentas do Serena e do RAG.

| Componente | Responsabilidade | Ferramenta |
| :--- | :--- | :--- |
| **Orquestrador** | Decompor PRDs em *tasks* atômicas | Compozy CLI |
| **Executor** | Implementar o código da *task* | GitHub Copilot CLI / Claude Code |
| **Contexto** | Fornecer busca semântica e LSP | Serena MCP + mcp-vector-search |

---

## Passo a Passo da Configuração

### 1. Preparar a Estrutura de Diretórios

O Compozy descobre agentes locais na pasta `.compozy/agents/` na raiz do seu projeto (ou globalmente em `~/.compozy/agents/`).

Crie a estrutura de diretórios para os nossos agentes especializados:

```powershell
New-Item -ItemType Directory -Force -Path .compozy/agents/techlead-architect
New-Item -ItemType Directory -Force -Path .compozy/agents/backend-implementor
New-Item -ItemType Directory -Force -Path .compozy/agents/code-reviewer
```

### 2. Configurar o Agente Tech Lead (Planejamento)

O *Tech Lead* precisa de ambas as ferramentas (RAG e Serena) para analisar a arquitetura e definir contratos antes da implementação.

Crie o arquivo `.compozy/agents/techlead-architect/mcp.json`:

```json
{
  "mcpServers": {
    "serena": {
      "command": "uv",
      "args": ["tool", "run", "serena", "--context=jb-copilot-plugin"]
    },
    "local-code-rag": {
      "command": "uv",
      "args": ["run", "mcp-vector-search", "run"]
    }
  }
}
```

Crie o arquivo `.compozy/agents/techlead-architect/AGENT.md`:

```markdown
---
title: Tech Lead Architect
description: Especialista em arquitetura, contratos e decomposição de tarefas.
ide: copilot
reasoning_effort: high
access_mode: full
---
Você é um Tech Lead de Engenharia de Software Especialista.
Sua missão é analisar requisitos, definir contratos (OpenAPI, eventos) e detalhar a arquitetura antes da implementação.

## Estratégia de Ferramentas Obrigatória
1. SEMPRE inicie usando a ferramenta `activate_project` do Serena MCP.
2. Use `local-code-rag` para buscar padrões arquiteturais existentes no projeto.
3. Use `get_symbol_overview` do Serena para entender componentes específicos antes de alterá-los.

Sempre exija aprovação antes de finalizar uma especificação técnica.
```

### 3. Configurar o Agente Backend (Implementação)

O *Backend Implementor* foca na execução cirúrgica. Ele depende primariamente do Serena MCP para navegar no código e garantir que a implementação siga as especificações exatas.

Crie o arquivo `.compozy/agents/backend-implementor/mcp.json`:

```json
{
  "mcpServers": {
    "serena": {
      "command": "uv",
      "args": ["tool", "run", "serena", "--context=jb-copilot-plugin"]
    }
  }
}
```

Crie o arquivo `.compozy/agents/backend-implementor/AGENT.md`:

```markdown
---
title: Backend Implementor
description: Engenheiro focado em implementação de código, testes unitários e padrões.
ide: copilot
reasoning_effort: medium
access_mode: full
---
Você é um Engenheiro Backend Especialista.
Sua missão é implementar as tarefas técnicas (tasks) seguindo rigorosamente as especificações.

## Estratégia de Ferramentas Obrigatória
1. SEMPRE inicie usando a ferramenta `activate_project` do Serena MCP.
2. Use `find_symbol` e `find_references` do Serena para mapear onde seu novo código deve ser injetado.
3. Implemente código funcional, sem erros de sintaxe, seguindo princípios SOLID e responsabilidade única.
4. Após a implementação, atualize o README.md e gere commits no formato Conventional Commits.
```

### 4. Configurar o Compozy

Crie o arquivo de configuração `.compozy/config.toml` na raiz do projeto para definir os padrões de execução e os tipos de tarefas suportadas:

```toml
[defaults]
ide = "copilot"
model = "claude-3-5-sonnet-20241022"
reasoning_effort = "medium"
access_mode = "full"
timeout = "15m"
auto_commit = false

[tasks]
types = ["frontend", "backend", "docs", "test", "infra", "refactor", "chore", "bugfix"]

[tasks.run]
include_completed = false
run_multiple_mode = "enqueued"

[tasks.run.parallel]
enabled = false
```

---

## Executando o Fluxo Integrado

Com os agentes configurados, você pode executar o fluxo completo do Compozy, beneficiando-se da inteligência local em cada etapa.

### Fase 1: Enriquecimento *Codebase-Aware*

Quando você iniciar o fluxo de criação de *tasks* a partir de uma especificação técnica (TechSpec), o Compozy pode usar o agente *Tech Lead* para explorar o repositório e enriquecer as tarefas:

```powershell
compozy tasks generate --agent techlead-architect
```

Neste momento, o agente invocará o RAG e o Serena para garantir que as *tasks* geradas respeitem os padrões existentes no código.

### Fase 2: Execução das Tarefas

Para executar a fila de tarefas geradas, invoque o Compozy especificando o agente de implementação:

```powershell
compozy tasks run --agent backend-implementor
```

O Compozy iniciará a execução da primeira *task*. O agente (via Copilot CLI) receberá a instrução da *task*, o contexto histórico (memória do Compozy) e o acesso aos servidores MCP locais (Serena). Ele navegará no código de forma autônoma, implementará a solução e aguardará sua aprovação.

### Fase 3: Execução Ad-Hoc

Se você precisar resolver um problema pontual sem passar por todo o pipeline SDD, pode invocar um agente diretamente:

```powershell
compozy exec --agent techlead-architect "Mapeie a comunicação entre o OrderService e o PaymentService e gere um diagrama C4."
```

O Compozy carregará o agente, injetará os servidores MCP (RAG + Serena) e executará a solicitação de forma isolada, mas mantendo o histórico na memória da sessão.

---

## Benefícios da Integração

1. **Memória Persistente**: Ao contrário do *chat* do IntelliJ, que perde o contexto quando a janela é fechada, o Compozy mantém um registro em *markdown* das decisões arquiteturais tomadas pelo *Tech Lead*, que são herdadas automaticamente pelo *Backend Implementor* nas *tasks* subsequentes.
2. **Isolamento de MCP Servers**: O *Backend Implementor* não é sobrecarregado com as ferramentas de RAG (que consomem mais *tokens*), pois seu `mcp.json` inclui apenas o Serena. O *Tech Lead* tem acesso a ambos.
3. **Independência de IDE**: Esta configuração permite que você execute a esteira de desenvolvimento a partir de qualquer terminal no Windows 11, sem depender exclusivamente da interface gráfica do IntelliJ, mantendo as mesmas capacidades avançadas de inteligência de código.

## Referências

[1] Compozy GitHub Repository. "Reusable Agents Documentation". [Link](https://github.com/compozy/compozy/blob/main/docs/reusable-agents.md)
[2] Compozy GitHub Repository. "Configuration Documentation". [Link](https://github.com/compozy/compozy/blob/main/docs/configuration.md)
