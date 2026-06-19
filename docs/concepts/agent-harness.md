# Agent Harness: A Engenharia por Trás da Autonomia

O desenvolvimento de software assistido por inteligência artificial ultrapassou a fase de geração isolada de trechos de código. Estamos na era dos agentes autônomos, onde sistemas não apenas sugerem implementações, mas planejam, executam, testam e corrigem falhas em *loops* contínuos de trabalho. Contudo, modelos de linguagem grandes (LLMs) são, em sua essência, motores probabilísticos de predição de *tokens*. Eles não possuem memória persistente, não conseguem executar comandos no terminal e não compreendem nativamente a estrutura de um repositório. Para que um modelo se transforme em um agente funcional, ele precisa de um **Harness**.

A equação fundamental que rege a nova engenharia de software assistida por IA é simples, porém profunda: **Agent = Model + Harness** [1] [2]. O *Harness* (ou "arnês", em tradução livre) engloba toda a infraestrutura, ferramentas, regras, *prompts* de sistema, gerenciamento de contexto e *loops* de orquestração que envolvem o modelo. Se você não está construindo o modelo em si, você está praticando a engenharia de *harness* [2].

Este documento explora o conceito de *Agent Harness*, suas dimensões arquiteturais, e como estruturar repositórios de forma que sejam legíveis não apenas para humanos, mas otimizados para a navegação autônoma de agentes de IA.

## Anatomia de um Harness

Um modelo isolado recebe texto e cospe texto. O *Harness* atua como a ponte entre esse texto e o mundo real. A Microsoft, ao descrever o funcionamento interno do GitHub Copilot no VS Code, divide as responsabilidades do *harness* em três pilares fundamentais: montagem de contexto, exposição de ferramentas e execução de ferramentas [3]. 

Para que o agente realize tarefas complexas, o *harness* implementa um ciclo contínuo conhecido como *Agent Loop* (frequentemente implementado como um padrão ReAct: *Reason*, *Act*, *Observe*) [2] [3]. A cada iteração, o *harness* constrói o *prompt* com o estado mais recente do repositório, envia ao modelo, valida a resposta, executa as ferramentas solicitadas (como `find_symbol` via Serena MCP ou `semantic_search` via RAG) e devolve os resultados para a próxima iteração.

### Controles de Feedforward e Feedback

Martin Fowler, através do trabalho da Thoughtworks, propõe um modelo mental que divide o *harness* em mecanismos de direcionamento prévio e correção posterior [1].

| Tipo de Controle | Direção | Descrição | Exemplos Práticos |
| :--- | :--- | :--- | :--- |
| **Guides** (*Feedforward*) | Antes da Ação | Antecipam o comportamento do agente e o direcionam para aumentar a probabilidade de acerto na primeira tentativa. | Instruções no `AGENTS.md`, definição de ferramentas MCP, convenções de arquitetura. |
| **Sensors** (*Feedback*) | Depois da Ação | Observam o resultado da ação e fornecem sinais para que o agente se autocorriga antes de exibir o resultado ao humano. | *Linters* estruturais, testes unitários automatizados, *logs* de erro capturados do terminal. |

Esses controles podem ser **computacionais** (determinísticos e rápidos, como um analisador estático de código) ou **inferenciais** (probabilísticos e custosos, como um subagente atuando como revisor de código) [1]. A orquestração eficiente de agentes de longa duração exige uma combinação robusta de ambos.

## A Solução para o "Context Rot" e Agentes de Longa Duração

Um dos maiores desafios na engenharia de *harness* é o *Context Rot* (apodrecimento de contexto). À medida que o agente trabalha, a janela de contexto se enche de tentativas falhas, *logs* extensos e históricos de navegação. A performance do modelo degrada rapidamente [2].

A Anthropic abordou esse problema em tarefas de longa duração introduzindo uma arquitetura de duas fases: um **agente inicializador** que configura o ambiente e define a lista de funcionalidades a serem desenvolvidas (geralmente em um arquivo JSON estruturado), seguido por **agentes de codificação** que trabalham de forma incremental, funcionalidade por funcionalidade [4].

O segredo para o sucesso contínuo é o uso do sistema de arquivos como a memória de longo prazo do agente [2]. Em vez de manter todo o histórico no contexto do LLM, o *harness* instrui o agente a registrar seu progresso em arquivos como `claude-progress.txt` e a realizar *commits* semânticos no Git. Assim, quando a janela de contexto é reiniciada ou compactada, o agente recupera rapidamente seu estado lendo o sistema de arquivos [4].

## Legibilidade para Agentes: O Repositório como Sistema de Registro

A equipe da OpenAI, ao construir um produto com zero linhas de código escritas manualmente e um milhão de linhas geradas por agentes (Codex), descobriu que a legibilidade do código para o agente é mais crítica do que para o humano [5]. 

O erro mais comum na construção de um *harness* documental é criar um arquivo `AGENTS.md` gigantesco com todas as regras do projeto. Isso falha porque o contexto é escasso, o excesso de regras gera paralisia, o documento fica obsoleto rapidamente e não pode ser validado mecanicamente [5].

A solução é utilizar o `AGENTS.md` apenas como um **índice** (*table of contents*), aplicando o princípio da revelação progressiva (*progressive disclosure*). O agente lê o índice e decide quais documentos aprofundar com base na tarefa atual.

### Exemplo Prático de Estrutura de Pastas Otimizada para Agentes

Abaixo, apresentamos uma estrutura de repositório inspirada na arquitetura utilizada pela OpenAI, projetada especificamente para maximizar a autonomia e a precisão dos agentes [5].

```text
meu-microservico/
├── .github/
│   ├── agents/                   # Definições de persona (TechLead, BackendDev)
│   └── prompts/                  # Tarefas fixas reutilizáveis (C4, OpenAPI)
├── docs/                         # Sistema de registro (System of Record)
│   ├── design-docs/              # Decisões arquiteturais (ADRs)
│   │   ├── index.md              # Índice da pasta
│   │   └── core-beliefs.md       # Princípios inegociáveis do projeto
│   ├── exec-plans/               # Memória de curto/médio prazo do agente
│   │   ├── active/               # Planos em execução atual
│   │   ├── completed/            # Histórico de planos finalizados
│   │   └── tech-debt-tracker.md  # Débito técnico registrado pelo agente
│   ├── product-specs/            # Especificações de negócio
│   └── references/               # Documentação de bibliotecas e frameworks
├── src/                          # Código-fonte da aplicação
├── AGENTS.md                     # O mapa principal (Ponto de entrada do agente)
├── ARCHITECTURE.md               # Visão macro de domínios e camadas
└── mcp.json                      # Configuração de ferramentas (RAG, Serena)
```

Nesta estrutura, o diretório `docs/` atua como o banco de dados do agente. Quando um agente atua no papel de *Tech Lead*, ele pode gerar um plano de execução detalhado em `docs/exec-plans/active/`. Posteriormente, um agente no papel de *Backend Developer* lê esse plano, implementa o código em `src/`, atualiza o rastreador de débito técnico e move o plano para `completed/`. Toda a comunicação entre agentes ocorre de forma assíncrona e auditável através do sistema de arquivos [4] [5].

## Decisões Arquiteturais no Design de Harness

Um estudo empírico recente analisou 70 projetos de sistemas de agentes e identificou que o *design space* de um *harness* é estruturado em torno de cinco dimensões principais [6]:

1. **Arquitetura de Subagentes**: Desde sistemas de agente único até hierarquias complexas de orquestração multiagente.
2. **Gerenciamento de Contexto**: Estratégias que variam de sessões efêmeras até persistência em banco de dados vetorial (RAG) e sistemas de arquivos.
3. **Sistemas de Ferramentas**: O ecossistema de *plugins*, integrações e servidores MCP (*Model Context Protocol*) que o agente pode invocar.
4. **Mecanismos de Segurança**: Controles de execução, isolamento em *sandboxes* e requisitos de aprovação humana (*human-in-the-loop*).
5. **Orquestração**: A lógica de roteamento e *handoff* (transferência de contexto) entre diferentes agentes especializados.

No projeto local configurado neste repositório, implementamos um *harness* que utiliza o **Serena MCP** para navegação estrutural (*guides*) e o **RAG Vetorial local** para busca de padrões (*memory*), criando um ambiente onde o agente possui as ferramentas necessárias para não apenas sugerir código, mas compreender profundamente a topologia do sistema antes de agir.

## Conclusão

A transição para um modelo de desenvolvimento *agent-first* exige uma mudança de mentalidade. O papel do engenheiro de software evolui da escrita manual de linhas de código para a **engenharia de sistemas de controle**. O foco passa a ser o desenho de ambientes, a especificação de intenções claras, a construção de servidores MCP que expõem ferramentas de domínio específico e a criação de *loops* de *feedback* que permitem aos agentes realizar trabalhos confiáveis de forma autônoma [1] [5]. 

Ao estruturar seu repositório pensando no *harness*, você não está apenas documentando o projeto; você está programando o comportamento do seu futuro colega de equipe artificial.

***

## Referências

[1] M. Fowler and B. Böckeler, "Harness engineering for coding agent users," Thoughtworks, Apr. 2026. [Online]. Available: https://martinfowler.com/articles/harness-engineering.html.

[2] V. Trivedy, "The Anatomy of an Agent Harness," LangChain Blog, Mar. 2026. [Online]. Available: https://www.langchain.com/blog/the-anatomy-of-an-agent-harness.

[3] J. Kasper, M. Rogge, and A. Munger, "The Coding Harness Behind GitHub Copilot in VS Code," Visual Studio Code Blog, May 2026. [Online]. Available: https://code.visualstudio.com/blogs/2026/05/15/agent-harnesses-github-copilot-vscode.

[4] Anthropic Engineering, "Effective harnesses for long-running agents," Anthropic, Nov. 2025. [Online]. Available: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents.

[5] R. Lopopolo, "Harness engineering: leveraging Codex in an agent-first world," OpenAI, Feb. 2026. [Online]. Available: https://openai.com/index/harness-engineering/.

[6] H. Wei, "Architectural Design Decisions in AI Agent Harnesses," arXiv:2604.18071v1 [cs.AI], Apr. 2026. [Online]. Available: https://arxiv.org/html/2604.18071v1.
