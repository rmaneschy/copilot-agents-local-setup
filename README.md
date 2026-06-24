# Copilot Agents Local Setup

## Visão Geral do Projeto

O projeto **Copilot Agents Local Setup** fornece os scripts, configurações e ferramentas necessários para provisionar um sistema de *Retrieval-Augmented Generation* (RAG) 100% local, voltado para a análise avançada de código-fonte. A solução foi concebida para operar em ambientes de desenvolvimento corporativos restritos, especificamente em máquinas com sistema operacional Windows 11, onde o usuário não possui privilégios de administrador e não há disponibilidade de contêineres Docker.

A integração principal ocorre com o **IntelliJ IDEA** (e opcionalmente VS Code) através do plugin **GitHub Copilot Chat**, utilizando o padrão *Model Context Protocol* (MCP). A solução combina **duas abordagens complementares**: busca semântica em linguagem natural (RAG Vetorial) e navegação estrutural determinística (Serena MCP via LSP).

> **Nota:** Os documentos conceituais sobre agentes, orquestradores e melhores práticas estão no repositório irmão [copilot-agents-setup](https://github.com/rmaneschy/copilot-agents-setup). Este repositório foca na **infraestrutura local** (instalação, configuração e operação), com exceção do [Comparativo de Frameworks SDD](docs/concepts/spec-driven-development-frameworks.md) que orienta a escolha de metodologia para o time.

---

## Arquitetura e Componentes da Solução

A arquitetura baseia-se na composição de ferramentas de código aberto e leves, garantindo privacidade absoluta (o código nunca sai da máquina para ser indexado) e baixo consumo de recursos do desenvolvedor.

| Componente | Função | Justificativa |
| :--- | :--- | :--- |
| **Ollama** | Motor local para modelos de linguagem (chat/completion). | Permite instalação em nível de usuário no Windows (sem admin). Utilizado para LLM local (chat), **não mais para embeddings** desde a v4 do mcp-vector-search. |
| **mcp-vector-search v4** | Servidor MCP em Python que realiza análise AST, chunking inteligente e indexação vetorial do código. | Fornece *tools* de busca semântica vetorial. Usa `sentence-transformers` (modelo `all-MiniLM-L6-v2`) para gerar embeddings localmente, sem depender do Ollama. |
| **LanceDB** | Banco de dados vetorial embutido (*serverless*). | Armazena os *embeddings* em disco de forma eficiente, sem utilizar o Docker. |
| **Serena MCP** | Servidor MCP patrocinado pela Microsoft que utiliza o *Language Server Protocol* (LSP). | Fornece navegação determinística no código (find_symbol, find_references), complementando a busca vetorial. Instala-se via `uv` sem privilégios de administrador. |

Para um aprofundamento técnico, consulte o documento de [Arquitetura da Solução](docs/architecture.md) e a [Análise Comparativa com Alternativas de Mercado](docs/comparativo-alternativas.md) (como Sourcebot, Continue.dev e Greptile).

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
├── setup.ps1                            # Setup completo (Ollama + LanceDB + detecção de hardware)
├── setup-vector-search.ps1              # Setup independente do mcp-vector-search (RAG)
├── apply-ollama-tweaks.ps1              # Aplica/troca tweaks do Ollama por perfil de hardware
├── setup-serena.ps1                     # Setup Serena MCP (uv + LSP)
├── setup-n8n.ps1                        # Setup n8n (orquestrador visual de agentes)
├── setup-mcp-inspector.ps1              # Executa MCP Inspector (debug visual de tools)
├── inspect-mcp.ps1                      # Verificação rápida de servidores MCP
├── setup-proxy-workaround.ps1           # Contorno para proxy corporativo com SSL
├── setup-alternative-node.ps1           # Setup alternativo via Node.js/Bun
├── index-workspace.ps1                  # Indexação do workspace para RAG
├── health-check.ps1                     # Verificação de saúde dos componentes
├── optimize-environment.ps1             # Otimização de desempenho (keep-alive, índices)
├── toggle-monitoring.ps1                # Habilitar/desabilitar monitoramento MCP
└── generate-dashboard.ps1               # Gerar dashboard HTML de desempenho

monitoring/
└── mcp-proxy-logger.py                  # Proxy transparente para logging JSON-RPC

docs/                                    # Documentação técnica da infraestrutura
├── architecture.md                      # Arquitetura detalhada da solução
├── comparativo-alternativas.md          # Comparação com Sourcebot, Continue.dev, Greptile
├── ollama-tweaks-e-perfis-hardware.md   # Tweaks do Ollama, KV Cache e perfis de hardware
└── concepts/
    └── spec-driven-development-frameworks.md  # Comparativo SDD (SpecKit, Superpowers, OpenSpec)
```

---

## Instalação e Configuração

O processo de instalação foi automatizado por meio de scripts PowerShell, projetados para rodar sem elevação de privilégios.

### Pré-requisitos

1. **Windows 11** (sem necessidade de privilégios administrativos).
2. **Python 3.11+** (pode ser instalado via Microsoft Store).
3. **Ollama** (opcional para LLM local; baixe em [ollama.com/download](https://ollama.com/download)). **Nota:** desde a v4 do mcp-vector-search, o Ollama **não é mais necessário para embeddings** — o modelo `all-MiniLM-L6-v2` é executado diretamente via `sentence-transformers`.
4. **IntelliJ IDEA** com o plugin **GitHub Copilot** (versão 1.5.57 ou superior, com Agent Mode e MCP habilitados).

### Passos para Instalação

1. Clone este repositório em sua máquina local.
2. Abra o PowerShell e navegue até a pasta do projeto.
3. Execute o script de configuração principal:

```powershell
.\scripts\setup.ps1
.\scripts\setup-serena.ps1
```

> **Atenção para usuários corporativos:** Se a sua rede utiliza um proxy com inspeção SSL/TLS, o script `setup.ps1` pode falhar no download do modelo com erro de `SHA256 digest`. Neste caso, utilize o script de contorno:
> ```powershell
> .\scripts\setup-proxy-workaround.ps1
> ```

Os scripts irão configurar o ambiente virtual Python, instalar o `mcp-vector-search` v4 (com `sentence-transformers` para embeddings locais), baixar o modelo de embedding `all-MiniLM-L6-v2` do HuggingFace (apenas na primeira execução), instalar o **Serena MCP** via `uv` (gerenciador de pacotes) e configurar o arquivo `mcp.json` na pasta de configuração do IntelliJ (`~/.config/github-copilot/intellij/`).

> **Ambiente offline / corporativo:** Após a primeira execução com internet (que baixa o modelo de ~90MB), o sistema funciona 100% offline. Para configurar o modo offline explicitamente:
> ```powershell
> .\scripts\setup-vector-search.ps1 -OfflineMode
> ```

*Nota: Existe também um script de setup alternativo (`setup-alternative-node.ps1`) baseado em Node.js/Bun, caso prefira não utilizar o Ollama.*

### Indexação do Workspace

Na v4 do mcp-vector-search, a indexação ocorre **automaticamente** na primeira busca semântica e é mantida atualizada via *file watching*. Para indexação manual ou cross-repository:

```powershell
# Indexar workspace específico (modo project)
.\scripts\setup-vector-search.ps1 -WorkspacePath "C:\Users\SEU_USUARIO\workspace\meu-projeto"

# Indexar todos os projetos (modo workspace — busca cross-repository)
.\scripts\setup-vector-search.ps1 -Scope workspace
```

O script `index-workspace.ps1` continua disponível para reindexação forçada:

```powershell
.\scripts\index-workspace.ps1 -Path "C:\Users\SEU_USUARIO\workspace"
```

---

## Utilização e Prompts Especializados

Uma vez configurado, o servidor MCP local expõe ferramentas de busca semântica para o GitHub Copilot. Você pode invocar os agentes e *prompts* diretamente no chat do IntelliJ para realizar tarefas complexas.

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

---

## Ferramentas Visuais (MCP Inspector e n8n)

Além do monitoramento via proxy, o projeto oferece duas ferramentas visuais complementares para teste, debug e orquestração de agentes.

### MCP Inspector (Debug Visual de Servidores)

O [MCP Inspector](https://github.com/modelcontextprotocol/inspector) é a ferramenta oficial do Model Context Protocol para testar e depurar servidores MCP. Ele fornece uma interface web interativa onde é possível invocar *tools*, consultar *resources* e testar *prompts* expostos pelos servidores locais.

```powershell
# Inspecionar o mcp-vector-search (padrão)
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

## Monitoramento e Dashboard

O projeto inclui ferramentas completas para monitorar a saúde do sistema e o desempenho dos agentes.

### Verificação de Saúde (Health Check)

Para verificar se todos os componentes (Ollama, Python, Serena, RAG) estão rodando corretamente:

```powershell
.\scripts\health-check.ps1
```

### Dashboard de Desempenho (MCP Proxy Logger)

Você pode habilitar o monitoramento avançado para ver **exatamente quais ferramentas os agentes estão usando**, quanto tempo demoram e se há gargalos. O sistema intercepta as chamadas JSON-RPC de forma transparente e gera um dashboard visual em HTML.

**1. Habilitar o monitoramento:**
```powershell
.\scripts\toggle-monitoring.ps1 -Enable
```
*(Reinicie o IntelliJ após habilitar)*

**2. Gerar e visualizar o dashboard:**
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
| [copilot-agents-setup](https://github.com/rmaneschy/copilot-agents-setup) | Estrutura de agentes, skills, instruções, prompts e documentação conceitual (SDD, MCP, Orquestradores, Agentes Agnósticos). |
| **Este repositório** | Scripts, configs e ferramentas para instalar e operar a infraestrutura local (Ollama, RAG, Serena, LanceDB). |

---

## Contribuições e Padrões

Este projeto segue rigorosamente os princípios SOLID, código limpo e responsabilidade única. A arquitetura foi desenhada para ser aberta à expansão (adição de novos agentes e parsers) e fechada para alteração estrutural.

Todas as implementações devem ser acompanhadas de atualizações neste `README.md`. Os *commits* devem obrigatoriamente seguir o formato *Conventional Commits* (ex: `feat: adiciona script de health check`, `docs: melhora documentação arquitetural`). Certifique-se de que o código submetido seja funcional e esteja livre de erros de sintaxe.
