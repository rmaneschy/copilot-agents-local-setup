# Melhores Práticas para Agentes Agnósticos a Plataformas

O desenvolvimento de software assistido por inteligência artificial ultrapassou a fase de *prompts* isolados. Estamos construindo ecossistemas de agentes autônomos que planejam, codificam e testam em conjunto. Contudo, o rápido surgimento de plataformas como GitHub Copilot Agent Mode, Cursor, Claude Code e Windsurf criou um novo desafio arquitetural: o **vendor lock-in de agentes**. 

Quando as regras de negócio, os *prompts* de orquestração e as ferramentas semânticas são fortemente acoplados ao formato proprietário de uma única plataforma, a organização perde a flexibilidade de migrar para modelos ou ecossistemas mais eficientes no futuro [1]. 

A equação para evitar essa armadilha baseia-se na separação de responsabilidades. O conhecimento do agente deve ser universal, enquanto apenas o "chassis" de execução deve ser específico da plataforma.

Este documento explora as melhores práticas para o desenvolvimento de agentes agnósticos, os padrões de orquestração recomendados pela indústria e utiliza o **Compozy** — um orquestrador *open source* — como estudo de caso prático para alcançar a verdadeira portabilidade.

---

## 1. O Paradoxo do Vendor Lock-in em Agentes de IA

O *vendor lock-in* em sistemas baseados em IA ocorre quando as automações, *workflows* e ferramentas de uma organização dependem exclusivamente do formato, protocolo ou infraestrutura de um único provedor [1]. Em arquiteturas de agentes, esse acoplamento manifesta-se em três dimensões:

1. **Plataforma de Execução:** O uso de formatos proprietários para definir a persona do agente (ex: o frontmatter YAML `.copilot/agents/*.agent.md` no GitHub Copilot ou o `.cursorrules` no Cursor).
2. **Orquestração de Tarefas:** O uso de mecanismos nativos e fechados para *handoffs* (passagem de bastão) entre agentes.
3. **Protocolo de Ferramentas:** A integração de APIs e scripts utilizando *function calling* proprietário em vez de padrões abertos.

A mitigação desse risco exige uma abordagem arquitetural deliberada, onde o comportamento do agente é abstraído da plataforma que o executa [2].

---

## 2. Os Três Níveis de Portabilidade

Para alcançar o agnosticismo, a arquitetura do agente deve ser dividida em camadas, garantindo que a inteligência e o contexto permaneçam portáveis.

### Nível 1: Conhecimento (Markdown-First)
A regra de ouro da portabilidade é que **95% do cérebro do agente deve ser texto puro em Markdown** [3]. Diretrizes de arquitetura, padrões de código, *prompts* de sistema e exemplos de implementação devem residir em arquivos `.md` universais. O formato Markdown é compreendido nativamente por qualquer LLM e não possui dependência de plataforma.

### Nível 2: Protocolo de Ferramentas (MCP)
As ferramentas que o agente utiliza para interagir com o mundo real (como buscar no código, ler banco de dados ou executar testes) não devem ser acopladas à API da OpenAI ou da Anthropic. A adoção do **Model Context Protocol (MCP)**, um padrão aberto introduzido pela Anthropic, garante que qualquer ferramenta construída seja compatível simultaneamente com Copilot, Cursor, Claude e Windsurf [4].

### Nível 3: Orquestração e Comunicação (ACP / A2A)
A comunicação entre agentes independentes deve ocorrer via protocolos padronizados. O **Agent Communication Protocol (ACP)**, mantido pela Linux Foundation (anteriormente liderado pela IBM), fornece uma interface RESTful para que agentes construídos em diferentes *frameworks* colaborem de forma assíncrona [5]. Paralelamente, o **Agent-to-Agent Protocol (A2A)**, originado no Google e também doado à Linux Foundation, estabelece padrões para descoberta *peer-to-peer* e negociação de capacidades em escala corporativa [6].

---

## 3. Padrões de Design para Agnosticismo

A construção de agentes confiáveis e portáteis exige a aplicação de padrões de *design* bem estabelecidos. A Microsoft e especialistas da indústria identificam padrões fundamentais de orquestração [7] [8]:

| Padrão de Design | Descrição | Nível de Acoplamento |
| :--- | :--- | :--- |
| **Single-Agent com Ferramentas** | Um único agente acessa múltiplas ferramentas MCP para resolver um problema. Ideal para tarefas delimitadas. | Baixo. Facilmente portável se as ferramentas usarem MCP. |
| **Sequential Orchestration (Pipeline)** | Agentes operam em uma cadeia linear (ex: *Draft* → *Review* → *Polish*). O *output* de um é o *input* do outro. | Médio. Exige um orquestrador externo para gerenciar o estado. |
| **Concurrent Orchestration (Fan-out/Fan-in)** | Múltiplos agentes analisam o mesmo problema em paralelo (ex: segurança, performance, acessibilidade) e um agente consolidador junta os resultados. | Alto. Requer gerenciamento complexo de concorrência. |
| **Manager-Worker (Supervisor)** | Um agente supervisor recebe a tarefa, quebra em subtarefas e delega para agentes especialistas, avaliando o resultado final. | Alto. Depende fortemente de protocolos como ACP ou A2A para *handoff*. |

Para manter o agnosticismo, a lógica de roteamento (o padrão de *design*) deve residir em um orquestrador independente, e não estar "hardcoded" nas instruções internas do agente.

---

## 4. Estudo de Caso: Compozy como Orquestrador Agnóstico

O **Compozy** é um orquestrador *open source* (MIT) escrito em Go, que exemplifica perfeitamente a arquitetura agnóstica. Ele não é um agente em si, mas um maestro que coordena mais de 40 agentes existentes (Claude Code, Codex, Cursor, Gemini, etc.) através de um *pipeline* estruturado [3].

### A Abordagem Markdown-First
No Compozy, cada fase do ciclo de desenvolvimento gera um artefato em Markdown puro [3]:
1. **Idea:** O usuário descreve a necessidade.
2. **PRD:** O agente gera o Documento de Requisitos do Produto (`prd-feature.md`).
3. **TechSpec:** O agente TechLead cria a especificação técnica (`techspec-feature.md`).
4. **Tasks:** A especificação é quebrada em tarefas atômicas (`001-task.md`).
5. **Execution:** Agentes executam as tarefas em paralelo.

### Configuração Portável vs. Proprietária

A principal diferença entre um ambiente acoplado (como o GitHub Copilot Agent Mode) e um ambiente agnóstico (como o Compozy) reside na definição da persona do agente.

No GitHub Copilot, um agente é definido com um *frontmatter* proprietário [9]:

```yaml
---
name: backend-developer
description: Especialista em Spring Boot
tools: ['serena/find_symbol', 'local-code-rag/search']
---
# Instruções...
```

No Compozy, a configuração é separada em arquivos padronizados, garantindo que o agente possa ser migrado para qualquer outra plataforma [3]:

1. **`AGENT.md`**: Contém exclusivamente as instruções em texto puro.
2. **`mcp.json`**: Define as ferramentas usando o padrão aberto MCP.
3. **`config.toml`**: Define o *runtime* de execução (ex: `--ide codex` ou `--ide claude`).

Essa separação garante que, se a organização decidir abandonar o GitHub Copilot e adotar o Claude Code amanhã, 100% do conhecimento contido no `AGENT.md` e no `mcp.json` será reaproveitado sem modificações.

---

## 5. Guia Prático: Como Escrever Prompts Portáteis

Ao escrever as instruções do seu agente (seja no `copilot-instructions.md`, `.cursorrules` ou `CLAUDE.md`), siga estas diretrizes para maximizar a portabilidade:

1. **Evite Sintaxe Específica de Plataforma:** Não utilize variáveis de *template* proprietárias (como `${{ workspace.files }}`) dentro do corpo das instruções. Prefira descrever o comportamento esperado em linguagem natural.
2. **Abstraia as Ferramentas:** Em vez de instruir o agente a "usar a ferramenta `copilot_search`", instrua-o a "utilizar a ferramenta de busca semântica disponível no ambiente". O orquestrador injetará a ferramenta correta via MCP.
3. **Estruture por Responsabilidade:** Mantenha um documento central (ex: `AGENTS.md`) apenas como um índice, utilizando o princípio da revelação progressiva (*progressive disclosure*) para que o agente leia arquivos específicos (`backend-guidelines.md`, `security-rules.md`) apenas quando necessário.

---

## 6. Conclusão

O agnosticismo em plataformas de agentes não significa rejeitar as facilidades oferecidas por ferramentas como GitHub Copilot ou Cursor. Significa, sim, tomar decisões arquiteturais conscientes sobre onde o conhecimento da empresa reside. 

Ao adotar o formato Markdown para instruções, o protocolo MCP para ferramentas e protocolos abertos como ACP/A2A para comunicação, as equipes de engenharia garantem que seus agentes de IA sejam ativos portáteis, resilientes e imunes ao *vendor lock-in*. Ferramentas como o Compozy demonstram que é possível orquestrar fluxos de trabalho complexos mantendo a total independência tecnológica.

---

## Referências

[1] S. Besen and A. Gutowska, "What is Agent Communication Protocol (ACP)?," IBM Think, 2025. [Online]. Available: https://www.ibm.com/think/topics/agent-communication-protocol.
[2] "AI vendor lock-in risks: the operational crisis CEOs must solve," Ability AI, Mar. 20, 2026. [Online]. Available: https://www.ability.ai/blog/ai-vendor-lock-in-risks.
[3] "Compozy: Open-source CLI that orchestrates AI-assisted development," Compozy, 2026. [Online]. Available: https://github.com/compozy/compozy.
[4] "Introducing the Model Context Protocol," Anthropic, Nov. 25, 2024. [Online]. Available: https://www.anthropic.com/news/model-context-protocol.
[5] "Agent Communication Protocol: Welcome," Agent Communication Protocol Dev, 2025. [Online]. Available: https://agentcommunicationprotocol.dev/introduction/welcome.
[6] "Announcing the Agent2Agent Protocol (A2A)," Google Developers Blog, Apr. 09, 2025. [Online]. Available: https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/.
[7] "AI Agent Orchestration Patterns," Azure Architecture Center, Microsoft, Feb. 12, 2026. [Online]. Available: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns.
[8] "Building AI Agents: A Platform-Agnostic Guide for Developers in 2025," MLVeda, 2025. [Online]. Available: https://www.mlveda.com/blog/building-ai-agents-a-platform-agnostic-guide-for-developers-in-2025.
[9] "Creating custom agents for Copilot cloud agent," GitHub Docs, 2026. [Online]. Available: https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents.
