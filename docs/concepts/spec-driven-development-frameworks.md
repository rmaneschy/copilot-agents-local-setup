# Spec-Driven Development (SDD): Comparativo de Frameworks

O desenvolvimento assistido por IA (vibe coding) funciona bem para tarefas pequenas, como refatorar um único arquivo ou escrever um script descartável. No entanto, quando uma feature exige a modificação de múltiplos arquivos, o verdadeiro desafio não é a implementação do código, mas sim a decisão arquitetural e o alinhamento de requisitos. É neste ponto que o Spec-Driven Development (SDD) se torna essencial.

O Spec-Driven Development transforma especificações de documentação passiva em contratos executáveis. A ideia central é simples: você define e refina o que será construído em uma especificação escrita antes que o agente gere qualquer linha de código. O fluxo consiste em três etapas fundamentais separadas por revisões humanas: Especificação (o que fazer), Plano (como fazer em passos) e Código (implementação) [1].

Este documento apresenta uma análise comparativa dos principais frameworks SDD disponíveis no mercado — **SpecKit**, **Superpowers**, **OpenSpec** — além da abordagem de **Modelo Puro**, fornecendo o contexto necessário para que a equipe tome uma decisão informada sobre qual caminho seguir na adoção de agentes autônomos.

---

## 1. SpecKit (GitHub)

Desenvolvido pelo GitHub, o SpecKit é um toolkit focado em rastreabilidade e padronização. Ele trata a especificação como a fonte da verdade e o artefato principal do processo [2].

O framework é agnóstico em relação ao agente utilizado, suportando ferramentas como GitHub Copilot, Claude Code e Cursor. O fluxo de trabalho é linear e guiado por comandos explícitos (slash commands) que geram documentos em um diretório `.speckit/`. A equipe começa definindo uma "constituição" do projeto, seguida pela especificação, plano e tarefas, antes de chegar à implementação.

**Exemplo Realista:**  
Uma equipe precisa adicionar um sistema de exportação de dados. O Tech Lead usa o comando `/speckit.specify` para criar a especificação. O documento gerado detalha os formatos suportados, limites de taxa e tratamento de falhas. Em seguida, `/speckit.plan` quebra isso em tarefas para o backend (geração de CSV) e frontend (botão de download). Se o desenvolvedor tentar mudar o formato de CSV para JSON durante a codificação, o agente o impedirá, pois o contrato da especificação não permite.

**Vantagens:**
- **Portabilidade:** Funciona com múltiplos agentes e IDEs.
- **Rastreabilidade:** Excelente para auditorias e compliance, pois mantém o histórico de decisões.
- **Governança:** A "constituição" garante que princípios arquiteturais sejam respeitados em todas as especificações.

**Desvantagens:**
- **Rigidez (Static Specs):** As especificações não se atualizam automaticamente se a implementação mudar, gerando divergência (*drift*) ao longo do tempo [3].
- **Overhead:** O processo de criação de artefatos é demorado, o que pode não compensar para features pequenas.

---

## 2. Superpowers (Prime Radiant)

Criado por Jesse Vincent, o Superpowers é o framework mais popular da categoria, com foco no processo em vez do artefato. Ele assume que o fluxo de trabalho (workflow) é a fonte da verdade [2].

Diferente do SpecKit, o Superpowers é um sistema baseado em *skills* (habilidades) que são acionadas automaticamente pelo contexto. Ele não exige que você digite comandos específicos; em vez disso, o agente percebe que você está planejando uma feature e aciona a skill de `brainstorming`. Ele impõe um rigoroso ciclo de Test-Driven Development (TDD) e delega tarefas para subagentes especializados.

**Exemplo Realista:**  
O desenvolvedor diz ao Claude Code: "Precisamos mudar a verificação de batimentos cardíacos de um limite fixo para uma análise do formato da curva". Em vez de codificar, o Superpowers aciona a skill de design. Ele faz perguntas sobre falsos positivos e edge cases. Após a aprovação do design, ele cria um plano e despacha um subagente para escrever testes falhos (RED), seguidos pelo código mínimo para passar (GREEN). Ao final, um subagente de Code Review avalia a qualidade antes do merge.

**Vantagens:**
- **Autonomia Disciplinada:** O agente pode trabalhar por horas sem desviar do plano, mantendo o rigor do TDD.
- **Subagentes:** Isola o contexto, enviando agentes "limpos" para revisar o código, evitando viés de confirmação.
- **Integração Nativa:** Funciona como um plugin profundo dentro do ambiente do agente (Claude, Cursor, etc.).

**Desvantagens:**
- **Complexidade:** Pode ser excessivamente burocrático para manutenções simples.
- **Foco Menor em Documentação:** O objetivo é entregar código testado, não manter uma biblioteca de especificações rastreáveis.

---

## 3. OpenSpec (Fission AI)

O OpenSpec adota uma abordagem "brownfield-first" (focada em sistemas legados). Ele entende que a maioria do desenvolvimento ocorre em bases de código existentes, não em projetos novos [4].

Seu diferencial é o uso de especificações delta: em vez de gerar um documento massivo com todo o sistema, ele gera apenas o que está mudando. O fluxo de trabalho é uma máquina de estados rigorosa: proposta, aplicação e arquivamento. As especificações vivem junto com o código-fonte, servindo como documentação viva.

**Exemplo Realista:**  
A equipe precisa adicionar autenticação de dois fatores (2FA) a um serviço Express.js existente. O OpenSpec gera uma proposta mostrando exatamente quais fluxos serão `MODIFICADOS` e quais serão `ADICIONADOS`. Durante a validação, a ferramenta alerta que o desenvolvedor esqueceu de especificar o cenário de recuperação de conta. A especificação delta é revisada e, após a implementação, o documento é arquivado no repositório como parte da documentação do sistema.

**Vantagens:**
- **Leveza:** As especificações delta reduzem o tempo de leitura e revisão.
- **Foco em Sistemas Existentes:** Lida excepcionalmente bem com a complexidade de bases de código maduras.
- **Documentação Viva:** As especificações arquivadas ajudam no onboarding de novos desenvolvedores.

**Desvantagens:**
- **Especificações Semi-vivas:** Embora melhores que o SpecKit, as propostas ainda não se atualizam automaticamente durante a implementação se houver mudanças de rota [3].
- **Sem Orquestração:** Não gerencia múltiplos agentes simultaneamente.

---

## 4. Modelo Puro (Sem Framework)

A abordagem de Modelo Puro consiste em utilizar apenas as instruções nativas do sistema (como `CLAUDE.md`, `.github/copilot-instructions.md` ou `AGENTS.md`) sem a instalação de frameworks de terceiros. A estrutura do SDD é mantida exclusivamente pela disciplina da equipe e por prompts bem elaborados.

Neste modelo, a equipe define diretrizes claras de que o agente (ex: Tech Lead Agent) deve sempre gerar um arquivo `spec.md` e aguardar aprovação antes de passar a tarefa para o agente de implementação (ex: Backend Agent).

**Exemplo Realista:**  
A equipe configura o repositório com um `AGENTS.md` que define o papel do Tech Lead. O desenvolvedor pede uma nova feature de mensageria via Kafka. O Tech Lead Agent, seguindo suas instruções sistêmicas, cria um documento de design arquitetural e um contrato OpenAPI. O desenvolvedor revisa manualmente, aprova, e então instrui o Backend Agent a ler o contrato e implementar os produtores e consumidores em Spring Boot.

**Vantagens:**
- **Zero Overhead:** Nenhuma dependência externa, instalação ou curva de aprendizado de novas ferramentas.
- **Flexibilidade Total:** A equipe pode adaptar o fluxo de trabalho exatamente às suas necessidades.
- **Ideal para Início:** Excelente para equipes que estão começando a explorar a especialização de agentes.

**Desvantagens:**
- **Dependência de Disciplina:** Se o desenvolvedor pedir para o agente "pular a especificação e ir direto pro código", não há um sistema (hard-gate) para impedi-lo.
- **Falta de Automação:** Transições de fase (do plano para o código, do código para o teste) devem ser gerenciadas manualmente pelo desenvolvedor.

---

## Comparativo e Decisão

Para auxiliar na escolha, a tabela abaixo resume as características de cada abordagem com base em critérios essenciais de engenharia de software [3]:

| Critério | SpecKit | Superpowers | OpenSpec | Modelo Puro |
| :--- | :--- | :--- | :--- | :--- |
| **Foco Principal** | Artefatos e Rastreabilidade | Processo e TDD | Sistemas Legados (Brownfield) | Flexibilidade e Simplicidade |
| **Integração** | CLI Independente | Plugin Nativo (Skill) | CLI e Slash Commands | Instruções Nativas (Markdown) |
| **Rigidez** | Alta (Hard-gates manuais) | Alta (Workflow forçado) | Média (Máquina de estados) | Baixa (Depende do usuário) |
| **Curva de Aprendizado** | Média | Alta | Média | Baixa |
| **Risco de Lock-in** | Baixo | Baixo | Baixo | Nulo |
| **Melhor Cenário** | Projetos com alta exigência de compliance | Desenvolvimento autônomo longo | Refatorações e features em código legado | Prototipagem e adoção inicial |

### Recomendação Estratégica

1. **Para iniciar a jornada (Curto Prazo):** Comece com o **Modelo Puro**. Utilize os arquivos de instrução do repositório (`copilot-agents-setup`) para criar personas (Tech Lead, Backend, QA). Isso treina a equipe a pensar em fases (Planejamento → Execução) sem o atrito de aprender uma nova ferramenta.
2. **Para sistemas complexos e legados:** Avalie o **OpenSpec**. Sua abordagem focada em deltas e integração nativa com o código existente o torna a opção mais pragmática para manutenção de software maduro.
3. **Para máxima autonomia e rigor técnico:** Se a equipe deseja que os agentes escrevam código com forte cobertura de testes (TDD) e realizem revisões cruzadas, o **Superpowers** é a escolha definitiva.

Independentemente da ferramenta escolhida, o princípio permanece: **o código é barato, a intenção é cara**. O Spec-Driven Development garante que a inteligência artificial seja usada para acelerar a construção do sistema correto, e não apenas para gerar código mais rápido.

---

## Referências

[1] Datacamp. "Spec-Driven Development with Claude Code: A Guided Tutorial". Disponível em: https://www.datacamp.com/tutorial/spec-driven-development-with-claude-code
[2] Phung, Truong. "Spec Kit vs. Superpowers — A Comprehensive Comparison & Practical Guide". Dev.to. Disponível em: https://dev.to/truongpx396/spec-kit-vs-superpowers-a-comprehensive-comparison-practical-guide-to-combining-both-52jj
[3] Kdosha, Itzhak Eretz. "I Tested Three Spec-Driven AI Tools. Here’s My Honest Take." Ran the Builder. Disponível em: https://ranthebuilder.cloud/blog/i-tested-three-spec-driven-ai-tools-here-s-my-honest-take/
[4] Fission AI. "OpenSpec: A lightweight spec-driven framework". Disponível em: https://openspec.dev/
