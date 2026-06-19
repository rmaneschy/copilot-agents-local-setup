# Spec-Driven Development com Compozy: Orquestrando a Autonomia

A inteligência artificial transformou a escrita de código, mas também introduziu um novo problema: o caos de *prompts* dispersos e o excesso de microgerenciamento por parte dos desenvolvedores. O **Spec-Driven Development (SDD)** surgiu para resolver isso, estabelecendo que a especificação (a *Spec*) deve ser a fonte da verdade. O **Compozy** é a ferramenta de linha de comando (*CLI*) de código aberto que materializa essa teoria em um fluxo de trabalho prático e automatizado [1] [2].

Criado pelo brasileiro Pedro Nauck, o Compozy não é um agente de inteligência artificial por si só. Trata-se de um orquestrador local que coordena mais de quarenta agentes de mercado (como Claude Code, GitHub Copilot CLI, Cursor e Gemini) em um *pipeline* estruturado, levando uma ideia desde a concepção até a entrega de código funcional (*Pull Request*), sem exigir que o desenvolvedor perca tempo supervisionando o terminal [1] [3].

## Por que o Compozy é Necessário?

O desenvolvimento assistido por IA frequentemente sofre de perda de contexto. Um desenvolvedor descreve uma tarefa, o agente gera o código, mas esquece as decisões arquiteturais na tarefa seguinte. O Compozy resolve esse problema introduzindo três conceitos fundamentais [1] [2]:

1. **Markdown como Contrato:** Todas as especificações, tarefas e memórias são salvas como arquivos Markdown simples. Isso significa que humanos podem ler, editar e versionar esses artefatos no Git com facilidade.
2. **Memória de Longo Prazo:** O sistema possui uma memória que se compacta automaticamente. As decisões tomadas na "Tarefa 1" são herdadas pela "Tarefa 2", evitando que o desenvolvedor precise repetir o contexto a cada interação.
3. **Execução Local (Local-First):** Sendo um binário único em Go sem dependências externas, o código-fonte nunca sai da máquina do usuário, garantindo privacidade e controle total [2].

## O Pipeline de 7 Fases do Compozy

O fluxo de trabalho do Compozy implementa o Spec-Driven Development através de sete fases rigorosas. O desenvolvedor pode intervir, editar os arquivos gerados e aprovar o avanço para a próxima etapa [1].

### 1. Ideia (Idea)
O processo começa com o desenvolvedor descrevendo o que deseja construir em linguagem natural, diretamente no terminal.

### 2. Documento de Requisitos (PRD)
A IA analisa a ideia e gera um Documento de Requisitos do Produto (PRD) estruturado. Este documento define o escopo, os casos de uso e os critérios de aceitação da funcionalidade.

### 3. Especificação Técnica (TechSpec)
Com o PRD aprovado, o sistema gera a Especificação Técnica. Este documento detalha a arquitetura, as restrições, os riscos e o plano de implementação técnica. É o coração do SDD.

### 4. Divisão de Tarefas (Tasks)
A Especificação Técnica é dividida em tarefas atômicas e independentes. O diferencial do Compozy nesta fase é o "enriquecimento sensível à base de código" (*codebase-aware enrichment*): agentes exploram o repositório para descobrir padrões e dependências, garantindo que as tarefas geradas respeitem a arquitetura existente [1].

### 5. Execução Paralela (Execution)
Nesta fase, o Compozy aciona os agentes escolhidos pelo desenvolvedor (ex: Claude Code ou Copilot) para executar as tarefas. As tarefas podem ser processadas em paralelo, com tentativas automáticas (*retries*) e isolamento de contexto [1].

### 6. Revisão Automatizada (Review)
O código gerado passa por um processo de revisão. O Compozy pode integrar-se com ferramentas externas (como CodeRabbit) ou usar agentes internos para apontar falhas, exigindo correções automáticas antes de prosseguir [2].

### 7. Memória (Memory)
O contexto da execução é compactado e salvo em arquivos de memória (ex: `compacted.md`), garantindo que os aprendizados e decisões arquiteturais sejam lembrados nas próximas funcionalidades desenvolvidas no projeto [1].

## Passo a Passo Prático

Para ilustrar a simplicidade do Compozy, veja como iniciar o desenvolvimento de um sistema de autenticação.

**Passo 1: Instalação e Configuração**
O Compozy é instalado como uma ferramenta de linha de comando. Após a instalação, você configura quais agentes deseja utilizar.

```bash
# Instalação via Homebrew (Mac/Linux)
brew install compozy/tap/compozy

# Configuração interativa dos agentes
compozy setup
```

**Passo 2: Iniciando o Pipeline**
Você inicia o fluxo passando a sua ideia. O Compozy criará a estrutura de pastas e iniciará a geração dos documentos.

```bash
compozy run --from idea "Criar um sistema de autenticação OAuth2 com suporte a Google e GitHub, usando JWT"
```

**Passo 3: Acompanhamento e Edição**
O Compozy criará uma pasta `.compozy/tasks/auth-system/` no seu repositório. Lá, você encontrará o `prd.md` e o `techspec.md`. Você pode abrir esses arquivos no seu editor, fazer ajustes manuais e, em seguida, permitir que o Compozy continue para a geração das tarefas e execução.

**Passo 4: Execução com o "Looper"**
Após aprovar as tarefas (que também são arquivos Markdown com metadados em YAML), o processo em segundo plano (chamado de *Looper*) assume o controle. Ele invoca o agente de IA configurado para escrever o código de cada tarefa, validando e iterando até que a funcionalidade esteja completa [3].

## Benefícios do SDD com Compozy

A adoção do Compozy transforma a dinâmica das equipes de engenharia [3]:

* **Fim da Ociosidade:** Os desenvolvedores deixam de "bancar a babá" do terminal esperando a IA gerar código linha a linha.
* **Padronização:** Todo o processo, da ideia ao código, segue um fluxo rastreável e auditável, essencial para equipes corporativas.
* **Agentes Reutilizáveis:** É possível criar configurações específicas de agentes para diferentes projetos, garantindo que as regras de negócio sejam sempre aplicadas [1].
* **Independência de Fornecedor:** O uso de protocolos abertos (como o *Agent Communication Protocol* - ACP) e arquivos Markdown garante que a equipe não fique presa a uma única ferramenta de IA [2].

Em suma, o Compozy eleva o Spec-Driven Development de uma teoria conceitual para uma prática automatizada, permitindo que a inteligência artificial assuma a execução braçal enquanto o engenheiro de software foca no que realmente importa: a arquitetura e a especificação.

## Referências

[1] Compozy, "Compozy | Open-source CLI that orchestrates AI-assisted development," Compozy.com. [Online]. Disponível: https://www.compozy.com/.

[2] M. J. Boyle, "Compozy: an AI development workflow tool written in Go," ByteSizeGo, Abr. 2026. [Online]. Disponível: https://www.bytesizego.com/blog/compozy-an-ai-dev-lifecycle-tool-written-in-go.

[3] P. Nauck, "Today we are (re-)launching Compozy as an AI SDLC!," LinkedIn, Jan. 2026. [Online]. Disponível: https://www.linkedin.com/posts/pedronauck_today-we-are-re-launching-compozy-as-an-activity-7415051450067845120-k-TK.
