# Instruções do Projeto: Copilot Agents Local Setup

## Contexto
Este repositório contém a configuração e os scripts para provisionar um sistema de inteligência de código local para desenvolvedores usando Windows 11 sem privilégios de administrador e sem Docker. A solução combina dois motores complementares:

1. **Knowledge Graph + Busca Semântica** (`codebase-memory-mcp`): Motor de code intelligence que indexa o código em um knowledge graph persistente, expondo 14 ferramentas MCP — busca semântica vetorial, call graph, análise de impacto, visão arquitetural, cross-service linking e queries Cypher-like. Binário estático único (C puro), zero dependências, 158 linguagens, 100% offline.
2. **Navegação Semântica via LSP** (Serena MCP): Ferramentas determinísticas de navegação por símbolo (find_symbol, find_references, find_implementations, symbol_overview).

Ambos se integram ao GitHub Copilot Chat (IntelliJ IDEA ou VS Code) via Model Context Protocol (MCP).

## Princípios Arquiteturais e de Código
- **Responsabilidade Única**: Cada script ou configuração deve ter um propósito claro (ex: setup do ambiente, definição de agente).
- **Reuso**: Prefira soluções que possam ser reaproveitadas em diferentes microserviços.
- **Leveza**: A solução prioriza ferramentas que não consomem recursos excessivos da máquina do desenvolvedor (ex: binário estático codebase-memory-mcp, Serena via uv).
- **Privacidade**: Todo o processamento de indexação, embedding e busca ocorre localmente. O código nunca sai da máquina.
- **Complementaridade**: O codebase-memory-mcp encontra conceitos por linguagem natural, traça call graphs e analisa impacto; o Serena navega pela árvore de dependências de forma determinística. Utilize ambos em conjunto.

## Estratégia de Ferramentas para Agentes

Ao responder perguntas sobre o código-fonte, os agentes devem seguir esta prioridade:

1. **Busca por conceito** (codebase-memory-mcp `semantic_query`): "onde a senha é validada?", "quem publica no tópico pedidos?"
2. **Análise estrutural** (codebase-memory-mcp `trace_call_path`, `get_architecture`, `detect_changes`): "quem chama esta função?", "qual o impacto desta mudança?"
3. **Navegação por símbolo** (Serena): "quais classes implementam esta interface?", "find_references deste método"
4. **Leitura direta** (read): Apenas quando o arquivo específico já é conhecido.

Evite usar `grep_search` ou `file_search` quando as ferramentas do codebase-memory-mcp ou Serena oferecem alternativas superiores.

## Padrões de Qualidade
- **Código Limpo**: Mantenha os scripts (PowerShell, Python) legíveis e bem documentados.
- **SOLID**: Sempre que aplicável em implementações de código, siga os princípios SOLID (aberto para expansão, fechado para alteração).
- **Linguagem**: Utilize uma linguagem acadêmica nas documentações, explicando o contexto e dando exemplos quando necessário.

## Commits e Atualizações
- Após qualquer implementação ou alteração significativa, o arquivo `README.md` DEVE ser atualizado para refletir o estado atual do projeto.
- Todos os commits devem seguir o padrão **Conventional Commits** (ex: `feat: adiciona script de setup`, `docs: atualiza arquitetura`).
- Realize commits apenas de código funcional, sem erros de sintaxe, e garantindo que os testes (se existirem) estejam passando.
- Se houver padrões preexistentes no repositório, as novas implementações devem segui-los estritamente.
