# Arquitetura da Solução: RAG Local para Código-Fonte com GitHub Copilot e MCP

## Visão Geral

A solução propõe um sistema de Retrieval-Augmented Generation (RAG) 100% local, focado em código-fonte, que se integra nativamente ao IntelliJ IDEA através do GitHub Copilot Chat usando o Model Context Protocol (MCP). A arquitetura foi desenhada especificamente para ambientes restritos: Windows 11 sem privilégios de administrador e sem Docker.

## Componentes da Arquitetura

1. **IntelliJ IDEA + GitHub Copilot Plugin**:
   - Atua como a interface principal do usuário.
   - O Copilot Chat em "Agent Mode" envia prompts e delega a busca semântica para o servidor MCP configurado localmente.
   - Utiliza a configuração `~/.config/github-copilot/intellij/mcp.json` para conectar-se ao servidor MCP local.

2. **mcp-vector-search (Servidor MCP)**:
   - Uma ferramenta open-source em Python projetada especificamente para busca semântica em código-fonte com integração MCP nativa.
   - **Banco de Dados Vetorial**: Utiliza **LanceDB**, um banco de dados vetorial serverless (file-based), eliminando a necessidade de Docker ou processos em background (como Qdrant ou ChromaDB server).
   - Realiza análise de Abstract Syntax Tree (AST) para entender a estrutura do código (classes, métodos, interfaces) em múltiplas linguagens.

3. **Ollama (Embeddings Locais)**:
   - Motor de execução de LLMs e modelos de embedding locais.
   - Pode ser instalado no Windows no diretório do usuário, sem necessidade de privilégios administrativos.
   - Utilizado para gerar embeddings rápidos e leves (ex: `nomic-embed-text` ou `all-minilm`) do código-fonte para armazenamento no LanceDB.

4. **GitHub Copilot Custom Agents (.github/agents)**:
   - Instruções customizadas em Markdown que definem "personas" ou "agentes" específicos para o Copilot.
   - Inclui prompts especializados para análise arquitetural e mapeamento de microserviços.

## Fluxo de Dados

1. **Ingestão (Indexação)**:
   - O desenvolvedor executa um script PowerShell que varre o diretório `~/workspace`.
   - O `mcp-vector-search` lê os arquivos de código, quebra em chunks semânticos (baseado em AST).
   - O Ollama gera os embeddings vetoriais para cada chunk.
   - Os chunks e embeddings são salvos localmente no LanceDB.

2. **Consulta (RAG)**:
   - O desenvolvedor faz uma pergunta no IntelliJ Copilot Chat.
   - O Copilot aciona o agente customizado, que por sua vez chama a tool de busca do servidor MCP local.
   - O servidor MCP converte a pergunta em embedding via Ollama, busca os chunks mais similares no LanceDB e retorna o contexto (código-fonte relevante) para o Copilot.
   - O Copilot LLM sintetiza a resposta final com base no contexto injetado e a exibe no IntelliJ.

## Justificativa das Escolhas Tecnológicas

- **Sem Docker e Sem Admin**: O uso de LanceDB (via biblioteca Python) e Ollama (modo portable/user-install) atende perfeitamente ao requisito de não usar Docker nem exigir elevação de privilégios.
- **Gratuidade e Privacidade**: Todos os componentes (Ollama, mcp-vector-search, LanceDB) são open-source e gratuitos. O código-fonte nunca sai da máquina para ser indexado, garantindo privacidade total.
- **Integração Copilot/IntelliJ**: O suporte recente a MCP no GitHub Copilot para JetBrains permite que o Copilot acesse ferramentas locais de forma padronizada.
