# Instruções do Projeto: Copilot Agents Local Setup

## Contexto
Este repositório contém a configuração e os scripts para provisionar um sistema RAG (Retrieval-Augmented Generation) local para código-fonte, focado em desenvolvedores usando Windows 11 sem privilégios de administrador e sem Docker. O objetivo é permitir que o GitHub Copilot Chat (via IntelliJ IDEA ou VS Code) consulte ativamente o código-fonte de todo o `~/workspace` do desenvolvedor usando o Model Context Protocol (MCP).

## Princípios Arquiteturais e de Código
- **Responsabilidade Única**: Cada script ou configuração deve ter um propósito claro (ex: setup do ambiente, definição de agente).
- **Reuso**: Prefira soluções que possam ser reaproveitadas em diferentes microserviços.
- **Leveza**: A solução prioriza ferramentas que não consomem recursos excessivos da máquina do desenvolvedor (ex: LanceDB, Ollama local, Python venv).
- **Privacidade**: Todo o processamento de embeddings e busca vetorial ocorre localmente.

## Padrões de Qualidade
- **Código Limpo**: Mantenha os scripts (PowerShell, Python) legíveis e bem documentados.
- **SOLID**: Sempre que aplicável em implementações de código, siga os princípios SOLID (aberto para expansão, fechado para alteração).
- **Linguagem**: Utilize uma linguagem acadêmica nas documentações, explicando o contexto e dando exemplos quando necessário.

## Commits e Atualizações
- Após qualquer implementação ou alteração significativa, o arquivo `README.md` DEVE ser atualizado para refletir o estado atual do projeto.
- Todos os commits devem seguir o padrão **Conventional Commits** (ex: `feat: adiciona script de setup`, `docs: atualiza arquitetura`).
- Realize commits apenas de código funcional, sem erros de sintaxe, e garantindo que os testes (se existirem) estejam passando.
- Se houver padrões preexistentes no repositório, as novas implementações devem segui-los estritamente.
