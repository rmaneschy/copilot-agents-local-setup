# Copilot Agents Local Setup

## Visão Geral do Projeto

O projeto **Copilot Agents Local Setup** fornece os scripts, configurações e ferramentas necessários para provisionar um ambiente de **code intelligence** 100% local, voltado para a análise avançada de código-fonte por agentes autônomos. A solução foi concebida para operar em ambientes de desenvolvimento corporativos restritos, especificamente em máquinas com sistema operacional Windows 11, onde o usuário não possui privilégios de administrador e não há disponibilidade de contêineres Docker.

A integração principal ocorre com o **IntelliJ IDEA** (e opcionalmente VS Code) através do plugin **GitHub Copilot Chat**, utilizando o padrão *Model Context Protocol* (MCP). A solução combina **duas abordagens complementares**: knowledge graph com busca semântica integrada (codebase-memory-mcp) e navegação estrutural determinística (Serena MCP via LSP).

> **Nota:** Os documentos conceituais sobre agentes, orquestradores e melhores práticas estão no repositório irmão [copilot-agents-setup](https://github.com/rmaneschy/copilot-agents-setup). Este repositório foca na **infraestrutura local** (instalação, configuração e operação), com exceção do [Comparativo de Frameworks SDD](docs/concepts/spec-driven-development-frameworks.md) que orienta a escolha de metodologia para o time.

---

## Arquitetura e Componentes da Solução

A arquitetura baseia-se na composição de ferramentas de código aberto e leves, garantindo privacidade absoluta (o código nunca sai da máquina para ser indexado) e baixo consumo de recursos do desenvolvedor.

| Componente | Função | Justificativa |
| :--- | :--- | :--- |
| **codebase-memory-mcp** | Motor de code intelligence que indexa o código em um knowledge graph persistente, expondo 14 ferramentas MCP (busca semântica, call graph, análise de impacto, arquitetura). | Binário estático único (C puro), zero dependências. Modelo de embedding (`nomic-embed-code`, 768d) compilado no binário. 158 linguagens via tree-sitter. 100% offline desde o primeiro uso. Substitui o mcp-vector-search v4 com abordagem plug-and-play. |
| **Serena MCP** | Servidor MCP patrocinado pela Microsoft que utiliza o *Language Server Protocol* (LSP). | Fornece navegação determinística no código (find_symbol, find_references), complementando o knowledge graph. Instala-se via `uv` sem privilégios de administrador. |
| **Ollama** (opcional) | Motor local para modelos de linguagem (chat/completion). | Permite instalação em nível de usuário no Windows (sem admin). Utilizado apenas para LLM local (chat), **não é necessário para code intelligence**. |

Para um aprofundamento técnico, consulte o documento de [Arquitetura da Solução](docs/architecture.md) e a [Análise Comparativa com Alternativas de Mercado](docs/comparativo-alternativas.md) (como Sourcebot, Continue.dev e Greptile).

---

## Evolução da Solução: de RAG Vetorial para Knowledge Graph

A solução evoluiu significativamente ao adotar o **codebase-memory-mcp** como motor principal de code intelligence, substituindo a abordagem anterior baseada em RAG vetorial (mcp-vector-search v4 + sentence-transformers + LanceDB).

| Aspecto | Antes (mcp-vector-search v4) | Agora (codebase-memory-mcp) |
| :--- | :--- | :--- |
| **Instalação** | Python venv + pip + download de modelo (~90MB) | 1 comando (`install.ps1`), binário estático (~15MB) |
| **Dependências** | Python 3.11+, sentence-transformers, LanceDB | Zero (binário auto-contido, C puro) |
| **Embedding** | Download separado do HuggingFace | Compilado no binário (`nomic-embed-code`, 768d) |
| **Linguagens** | Limitado (parsers Python) | 158 linguagens (tree-sitter vendored) |
| **Abordagem** | Busca vetorial semântica apenas | Knowledge graph + busca semântica + call graph + cross-service |
| **MCP Tools** | 3-5 tools | 14 tools (search, trace, architecture, impact, Cypher) |
| **Offline** | Após download inicial do modelo | 100% offline desde o primeiro uso |
| **Cross-service** | Não suportado | HTTP, gRPC, GraphQL, pub-sub |
| **Team sharing** | Não suportado | `.codebase-memory/graph.db.zst` commitável via git |
| **Benchmark** | — | 99% token reduction, queries <1ms, Linux kernel (28M LOC) em 3 min |

O script legado `setup-vector-search.ps1` permanece disponível para cenários de migração, mas o **setup recomendado** agora utiliza `setup-codebase-memory.ps1`.

---

## Estrutura do Repositório

```text
.github/
├── agents/                              # Agentes especializados para uso com RAG + Serena
│   ├── techlead-architecture.md         #   Análise arquitetural de microserviços
│   ├── techlead-c4-diagram.md           #   Geração de diagramas C4 Container
│   ├── techlead-communication.md        #   Mapeamento de comunicação entre serviços
│   └── techlead-data-contracts.md       #   Contratos de dados, auth e dependências
├── prompts/                             # Prompts prontos para uso no Copilot Chat
│   ├── analyze-service.prompt.md        #   Análise de fluxo de ponta a ponta
│   ├── generate-c4-diagram.prompt.md    #   Gerar diagrama C4 com evidências
│   ├── map-communication.prompt.md      #   Mapear dependências entre serviços
│   ├── query-authentication.prompt.md   #   Consultar autenticação/autorização
│   ├── query-database-access.prompt.md  #   Consultar acessos a banco de dados
│   └── query-openapi-dependencies.prompt.md # Consultar dependências de contratos
└── copilot-instructions.md              # Instruções de contexto global

.vscode/
├── mcp.json                             # Configuração MCP padrão (RAG + Serena)
└── mcp-with-monitoring.json             # Configuração MCP com proxy de monitoramento

scripts/                                 # Automação de Setup (PowerShell)
├── setup.ps1                            # Setup completo (detecção de hardware + componentes)
├── setup-codebase-memory.ps1            # [RECOMENDADO] Setup plug-and-play do codebase-memory-mcp
├── setup-phoenix.ps1                    # [NOVO] Setup Arize Phoenix (observabilidade de agentes)
├── setup-vector-search.ps1              # [LEGADO] Setup do mcp-vector-search v4 (RAG vetorial)
├── apply-ollama-tweaks.ps1              # Aplica/troca tweaks do Ollama por perfil de hardware
├── setup-serena.ps1                     # Setup Serena MCP (uv + LSP)
├── setup-n8n.ps1                        # Setup n8n (orquestrador visual de agentes)
├── setup-mcp-inspector.ps1              # Executa MCP Inspector (debug visual de tools)
├── inspect-mcp.ps1                      # Verificação rápida de servidores MCP
├── setup-proxy-workaround.ps1           # Contorno para proxy corporativo com SSL
├── setup-alternative-node.ps1           # Setup alternativo via Node.js/Bun
├── index-workspace.ps1                  # Indexação recursiva (descobre repos via .git)
├── health-check.ps1                     # Verificação de saúde dos componentes
├── optimize-environment.ps1             # Otimização de desempenho (keep-alive, índices)
├── toggle-monitoring.ps1                # Habilitar/desabilitar monitoramento MCP
└── generate-dashboard.ps1               # Gerar dashboard HTML de desempenho

monitoring/
└── mcp-proxy-logger.py                  # Proxy transparente para logging JSON-RPC + export OTEL

docs/                                    # Documentação técnica da infraestrutura
├── architecture.md                      # Arquitetura detalhada da solução
├── comparativo-alternativas.md          # Comparação com Sourcebot, Continue.dev, Greptile
├── guia-observabilidade-phoenix.md      # Guia completo do Arize Phoenix (traces, logs, recursos)
├── ollama-tweaks-e-perfis-hardware.md   # Tweaks do Ollama, KV Cache e perfis de hardware
└── concepts/
    └── spec-driven-development-frameworks.md  # Comparativo SDD (SpecKit, Superpowers, OpenSpec)
```

---

## Instalação e Configuração

O processo de instalação foi automatizado por meio de scripts PowerShell, projetados para rodar sem elevação de privilégios.

### Pré-requisitos

1. **Windows 11** (sem necessidade de privilégios administrativos).
2. **IntelliJ IDEA** com o plugin **GitHub Copilot** (versão 1.5.57 ou superior, com Agent Mode e MCP habilitados).
3. **Conexão com internet** (apenas para o download inicial do binário, ~15MB; após isso, 100% offline).
4. **Ollama** (opcional, apenas se desejar LLM local para chat; baixe em [ollama.com/download](https://ollama.com/download)).

> **Nota:** Python, Node.js, Docker e API keys **não são mais necessários** para a solução principal de code intelligence.

### Passos para Instalação (Recomendado)

1. Clone este repositório em sua máquina local.
2. Abra o PowerShell e navegue até a pasta do projeto.
3. Execute o script de configuração principal:

```powershell
# Instalar codebase-memory-mcp (code intelligence via knowledge graph)
.\scripts\setup-codebase-memory.ps1

# Instalar Serena MCP (navegação LSP determinística)
.\scripts\setup-serena.ps1
```

Isso é tudo. O `setup-codebase-memory.ps1` realiza:

1. Download do binário estático (~15MB) com verificação SHA-256
2. Instalação em `%LOCALAPPDATA%\Programs\codebase-memory-mcp`
3. Adição ao PATH do usuário (sem admin)
4. Configuração automática do `mcp.json` para GitHub Copilot no IntelliJ
5. Opcionalmente, indexação inicial do workspace

> **Variante com visualização 3D do knowledge graph:**
> ```powershell
> .\scripts\setup-codebase-memory.ps1 -Variant ui
> # Abre http://localhost:9749 para explorar o grafo interativamente
> ```

### Indexação do Workspace

A indexação ocorre **automaticamente** na primeira busca semântica via Copilot. Para indexação manual ou antecipada, o script `index-workspace.ps1` percorre o workspace **recursivamente**, identifica cada repositório pela presença da pasta `.git` e indexa individualmente:

```powershell
# Indexar todos os repositórios em ~/workspace (recursivo, profundidade 3)
.\scripts\index-workspace.ps1

# Listar repositórios que seriam indexados (sem executar)
.\scripts\index-workspace.ps1 -DryRun

# Indexar apenas repos que começam com "ms-", excluindo legados
.\scripts\index-workspace.ps1 -Include "ms-*" -Exclude "*-legacy"

# Re-indexação completa forçada, 4 repos em paralelo
.\scripts\index-workspace.ps1 -Force -Parallel 4

# Workspace customizado com profundidade máxima de 2
.\scripts\index-workspace.ps1 -Path "C:\projetos" -MaxDepth 2
```

O script utiliza uma estratégia **greedy-stop**: ao encontrar um `.git`, indexa aquele diretório e não desce em subdiretórios (evitando submodules duplicados). Ao final, exibe um relatório com status de cada repositório.

O índice é mantido atualizado automaticamente via **git-based change detection** — o script só é necessário para a indexação inicial ou re-indexação forçada.

### Compartilhamento de Índice com o Time

O knowledge graph pode ser compartilhado via git, evitando que cada desenvolvedor precise reindexar do zero:

```powershell
# Commitar o índice comprimido
git add .codebase-memory/graph.db.zst
git commit -m "chore: atualiza índice do knowledge graph"

# Colegas fazem incremental diff (não full reindex)
git pull  # índice atualizado automaticamente
```

---

## Ferramentas MCP Disponíveis (14 tools)

O codebase-memory-mcp expõe 14 ferramentas via MCP que o GitHub Copilot pode invocar automaticamente no Agent Mode:

| Ferramenta | Função |
| :--- | :--- |
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

## Utilização e Prompts Especializados

Uma vez configurado, o servidor MCP local expõe as ferramentas de code intelligence para o GitHub Copilot. Você pode invocar os agentes e *prompts* diretamente no chat do IntelliJ para realizar tarefas complexas.

### 1. Análise Arquitetural de Serviço

Para analisar o fluxo de ponta a ponta de um microserviço, utilize o agente de arquitetura:

> "Ative o projeto do serviço <NOME_DO_SERVICO> com Serena.
> Analise o fluxo arquitetural de ponta a ponta: endpoints de entrada, controllers/handlers, services/use cases, repositories/DAOs, chamadas HTTP/gRPC externas, publicação ou consumo de mensagens, acesso a banco, tratamento de erro, autenticação/autorização e observabilidade.
> Use ferramentas semânticas como visão geral de símbolos, busca por símbolo e referências. Retorne uma explicação com evidências por arquivo e símbolo. Não faça alterações."

### 2. Mapeamento de Comunicação entre Microserviços

Para descobrir relações de dependência no seu *workspace*:

> "Na raiz C:\Users\SEU_USUARIO\workspace, descubra relações entre microserviços. Procure: URLs internas, nomes de serviços em variáveis de ambiente, clients Feign, WebClient, RestTemplate, Axios, fetch, gRPC, protobuf, tópicos Kafka/RabbitMQ/SQS/PubSub, consumers/producers, OpenAPI clients, Helm values, Kubernetes Service/Ingress, docker-compose service names.
> Gere uma matriz: origem | destino | protocolo | evidência | criticidade | observações."

### 3. Geração de Diagramas C4

Para obter uma visão visual da arquitetura baseada em código real:

> "Gere um diagrama C4 Container da plataforma com evidências de código."

### 4. Consultas sobre Contratos e Segurança

Você pode fazer perguntas direcionadas, como:
- "Quais microserviços gravam na base de pedidos?"
- "Quais serviços dependem deste contrato OpenAPI?"
- "Onde a autenticação é validada e quais serviços ignoram autorização?"

### 5. Análise de Impacto (Novo)

Com o codebase-memory-mcp, é possível analisar o impacto de mudanças antes de fazer commit:

> "Analise o impacto das minhas mudanças atuais (git diff). Quais funções são afetadas? Qual o risco de regressão?"

### 6. Dead Code Detection (Novo)

Para identificar código morto no projeto:

> "Encontre funções que nunca são chamadas neste projeto. Exclua entry points e handlers de framework."

---

## Ferramentas Visuais (MCP Inspector e n8n)

Além do monitoramento via proxy, o projeto oferece duas ferramentas visuais complementares para teste, debug e orquestração de agentes.

### MCP Inspector (Debug Visual de Servidores)

O [MCP Inspector](https://github.com/modelcontextprotocol/inspector) é a ferramenta oficial do Model Context Protocol para testar e depurar servidores MCP. Ele fornece uma interface web interativa onde é possível invocar *tools*, consultar *resources* e testar *prompts* expostos pelos servidores locais.

```powershell
# Inspecionar o codebase-memory-mcp (padrão)
.\scripts\setup-mcp-inspector.ps1

# Inspecionar o Serena MCP
.\scripts\setup-mcp-inspector.ps1 -Server serena

# Inspecionar um servidor customizado
.\scripts\setup-mcp-inspector.ps1 -Server custom -CustomCommand "node C:\meu-server\index.js"
```

A interface estará disponível em `http://localhost:6274`. Não requer instalação global; utiliza `npx` diretamente.

### n8n (Orquestrador Visual de Agentes)

O [n8n](https://n8n.io/) é uma plataforma *fair-code* de automação de workflows com suporte nativo ao MCP. Ele permite desenhar fluxos multi-agentes em um canvas visual, conectando LLMs locais (Ollama), servidores MCP e integrações externas (Jira, GitHub, Slack).

```powershell
# Instalar o n8n localmente (primeira vez)
.\scripts\setup-n8n.ps1

# Iniciar o n8n (uso diário)
.\scripts\setup-n8n.ps1 -Start

# Remover o n8n
.\scripts\setup-n8n.ps1 -Uninstall
```

A interface estará disponível em `http://localhost:5678`. Para conectar os servidores MCP locais, utilize o nó **MCP Client Tool** no canvas do n8n.

### Verificação Rápida de Servidores MCP

Para verificar rapidamente quais servidores MCP estão disponíveis e seus binários:

```powershell
.\scripts\inspect-mcp.ps1
```

---

## Monitoramento e Observabilidade

O projeto inclui ferramentas completas para monitorar a saúde do sistema, o desempenho dos agentes e o fluxo de decisões via traces.

### Arize Phoenix (Observabilidade de Agentes)

O **Arize Phoenix** é a plataforma open-source de observabilidade que permite visualizar o fluxo completo de decisões dos agentes — quais tools foram chamadas, em que ordem, quanto tempo levaram e se houve erros. Funciona 100% local via `pip install`, sem Docker ou admin.

```powershell
# Instalar Phoenix
.\scripts\setup-phoenix.ps1

# Instalar e iniciar (modo air-gapped para corporativo)
.\scripts\setup-phoenix.ps1 -Start -AirGapped

# Verificar status
.\scripts\setup-phoenix.ps1 -Status

# Parar
.\scripts\setup-phoenix.ps1 -Stop
```

Acesse a UI em `http://localhost:6006` para visualizar traces em árvore, filtrar por latência/erro e analisar padrões de uso. Para detalhes completos, consulte o **[Guia de Observabilidade Phoenix](docs/guia-observabilidade-phoenix.md)**.

### Verificação de Saúde (Health Check)

Para verificar se todos os componentes (codebase-memory-mcp, Serena, Phoenix, Ollama) estão rodando corretamente:

```powershell
.\scripts\health-check.ps1
```

### Dashboard de Desempenho (MCP Proxy Logger)

O monitoramento avançado intercepta chamadas JSON-RPC de forma transparente e pode operar em dois modos:

- **Modo JSONL** (padrão): Registra em `~/.copilot-metrics/calls.jsonl` para análise offline
- **Modo JSONL + Phoenix**: Exporta traces OTEL para o Phoenix (requer flag `--phoenix`)

**1. Habilitar o monitoramento (com Phoenix):**
```powershell
.\scripts\toggle-monitoring.ps1 -Enable -Phoenix
```
*(Reinicie o IntelliJ após habilitar)*

**2. Gerar e visualizar o dashboard HTML:**
```powershell
.\scripts\generate-dashboard.ps1
```

**3. Desabilitar o monitoramento:**
```powershell
.\scripts\toggle-monitoring.ps1 -Disable
```

### Otimização de Desempenho

Para entender em profundidade como cada configuração do Ollama afeta o desempenho dos agentes autônomos (incluindo KV Cache, Flash Attention e perfis por hardware), consulte o documento **[Ollama: Tweaks, KV Cache e Perfis de Hardware](docs/ollama-tweaks-e-perfis-hardware.md)**.

### Aplicação de Tweaks do Ollama

Para aplicar ou trocar as configurações de performance do Ollama sem executar o setup completo:

```powershell
# Detectar hardware e aplicar perfil automaticamente
.\scripts\apply-ollama-tweaks.ps1

# Forçar perfil específico
.\scripts\apply-ollama-tweaks.ps1 -Profile power

# Simular sem aplicar (dry-run)
.\scripts\apply-ollama-tweaks.ps1 -DryRun

# Verificar configurações ativas
.\scripts\apply-ollama-tweaks.ps1 -Verify

# Restaurar padrões de fábrica
.\scripts\apply-ollama-tweaks.ps1 -Reset
```

Para maximizar a velocidade de resposta dos agentes e reduzir consumo de recursos, execute o script de otimização:

```powershell
.\scripts\optimize-environment.ps1 -All
```

Este script configura o Ollama keep-alive (modelo permanente em memória), cria índices vetoriais e escalares no LanceDB (até 46x menos comparações) e executa compactação de fragmentos.

---

## Repositório Irmão

| Repositório | Propósito |
| :--- | :--- |
| [copilot-agents-setup](https://github.com/rmaneschy/copilot-agents-setup) | Estrutura de agentes, skills, instruções, prompts e diretrizes para o agente autônomo de desenvolvimento. |
| **Este repositório** | Scripts, configs e ferramentas para instalar e operar a infraestrutura local (codebase-memory-mcp, Serena, Ollama). |

---

## Contribuições e Padrões

Este projeto segue rigorosamente os princípios SOLID, código limpo e responsabilidade única. A arquitetura foi desenhada para ser aberta à expansão (adição de novos agentes e parsers) e fechada para alteração estrutural.

Todas as implementações devem ser acompanhadas de atualizações neste `README.md`. Os *commits* devem obrigatoriamente seguir o formato *Conventional Commits* (ex: `feat: adiciona script de health check`, `docs: melhora documentação arquitetural`). Certifique-se de que o código submetido seja funcional e esteja livre de erros de sintaxe.
