# Spec-Driven Development: Especificações como Código na Era dos Agentes Autônomos

## Introdução

Durante décadas, o código foi o artefato soberano do desenvolvimento de software. Documentos de requisitos existiam, mas se tornavam obsoletos. Diagramas de design eram desenhados, mas apodreciam. Testes eram escritos, mas frequentemente após o fato. O código — qualquer que fosse seu comportamento real — tornava-se a verdade de facto do sistema [1].

O **Spec-Driven Development** (SDD) inverte essa hierarquia: a especificação torna-se a fonte de verdade, e o código passa a ser um artefato derivado — gerado, implementado ou verificado contra ela. Em vez de codificar primeiro e documentar depois (ou nunca), equipes escrevem especificações claras do comportamento pretendido, e então geram ou verificam código contra essas especificações.

> **Princípio Central**: Em Spec-Driven Development, o código é o detalhe de implementação da especificação — não o contrário. A spec declara a intenção; o código a realiza. [1]

Esta abordagem ganhou relevância crítica com a ascensão dos agentes autônomos de codificação. Conforme o ThoughtWorks Technology Radar Vol. 33 (Novembro 2025), SDD foi posicionado no ring **"Assess"**, reconhecendo-o como uma das práticas emergentes mais importantes do ano [2].

---

## Por Que SDD Importa Agora

Três forças convergiram entre 2025 e 2026 que tornaram o SDD indispensável para equipes que utilizam agentes de IA em produção.

A primeira força é a **escala das vulnerabilidades geradas por IA**. Estudos demonstram que LLMs geram código vulnerável em taxas que variam de 9,8% a 42,1% dependendo do benchmark utilizado [3]. Até fevereiro de 2026, mais de 110.000 issues introduzidos por IA sobreviviam em repositórios de produção [3]. Especificações executáveis atuam como gates de validação ativa contra exatamente essas falhas.

A segunda força é a **necessidade de governança em arquiteturas distribuídas**. Segundo o relatório State of AI 2026 da Deloitte, apenas uma em cada cinco empresas possui um modelo maduro de governança para agentes autônomos de IA [3]. Sem especificações estruturadas governando a coordenação cross-service, equipes enfrentam falhas de integração compostas à medida que suas arquiteturas multi-repositório escalam.

A terceira força é o **problema fundamental do "vibe coding"**. Quando um desenvolvedor solicita "Adicione compartilhamento de fotos ao app", o agente precisa adivinhar: qual formato? Qual modelo de permissões? Quais limites de tamanho? Storage em nuvem ou local? O resultado é código plausível que faz dezenas de suposições não declaradas — muitas delas incorretas [1]. Com uma especificação, essas ambiguidades são eliminadas antes da geração.

---

## O Espectro de Especificação

Nem todas as abordagens spec-driven são iguais. O paper acadêmico "Spec-Driven Development: From Code to Contract in the Age of AI Coding Assistants" (arXiv, Fev. 2026) define três níveis de rigor, cada um adequado a contextos diferentes [1]:

| Nível | Papel da Spec | Papel do Código | Quando Usar |
| :--- | :--- | :--- | :--- |
| **Spec-First** | Guia e restringe a geração inicial | Artefato primário pós-implementação | Equipes iniciando SDD; protótipos |
| **Spec-Anchored** | Governa com checkpoints e constraints constitucionais | Artefato validado continuamente | Sistemas de produção; auditoria |
| **Spec-as-Source** | Fonte literal do código | Artefato gerado (nunca editado manualmente) | Domínios com geração madura (OpenAPI, Simulink) |

O nível **Spec-First** é o ponto de entrada. A especificação é escrita antes da implementação, garantindo clareza inicial, mas o código se torna o artefato primário após a implementação. É prático para equipes que não podem se comprometer com manutenção contínua de specs.

O nível **Spec-Anchored** trata a spec como documento vivo que evolui com o codebase. Mudanças de comportamento exigem atualizar tanto a spec quanto o código. Testes automatizados — tipicamente derivados da spec — garantem alinhamento. Se divergirem, testes falham, fornecendo feedback imediato. Este é o **sweet spot para a maioria dos sistemas de produção** [1].

O nível **Spec-as-Source** é o mais radical: a especificação é o único artefato que humanos editam diretamente. Código é inteiramente gerado e nunca modificado manualmente. Já é prática padrão em domínios como geração de stubs de API a partir de OpenAPI ou código certificado C a partir de modelos Simulink na indústria automotiva [1].

---

## O Workflow SDD em 4 Fases

O workflow canônico do SDD, conforme formalizado pelo GitHub Spec-Kit [4] e validado pelo paper acadêmico [1], segue quatro fases sequenciais. Cada fase produz um artefato que restringe e guia a próxima, criando uma cadeia de accountability da intenção à implementação.

### Fase 1: Specify (O Quê)

A fase de especificação responde à pergunta fundamental: **o que o software deve fazer?** O output é uma especificação funcional descrevendo comportamento, requisitos e critérios de aceitação — crucialmente, sem prescrever detalhes de implementação.

Conforme Addy Osmani (Google Chrome) recomenda, o foco deve estar em outcomes, não em implementação [5]:

> "Não escreva 'construa um fluxo de auth'. Escreva algo como: 'Um usuário pode se cadastrar com email/senha, receber um email de verificação, e fazer login sem erro. A sessão persiste entre refreshes de página.'"

### Fase 2: Plan (Como)

A fase de planejamento traduz a especificação funcional em decisões técnicas: stack, arquitetura, constraints, integrações. É aqui que o "how" entra, separado do "what" da fase anterior.

O GitHub Spec-Kit implementa isso com o comando `/speckit.plan`, onde o desenvolvedor fornece suas escolhas técnicas e o agente gera um plano de implementação compreensivo [4].

### Fase 3: Tasks (Divisão)

A especificação e o plano são decompostos em tarefas atômicas — pequenas, revisáveis, testáveis isoladamente. Cada tarefa resolve uma peça específica do quebra-cabeça, seguindo o princípio de que **pedir demais de uma vez é o maior modo de falha dos agentes** [3].

### Fase 4: Implement (Execução)

O agente executa as tarefas uma a uma (ou em paralelo quando não tocam os mesmos arquivos). Em vez de revisar dumps de código de mil linhas, o desenvolvedor revisa mudanças focadas que resolvem problemas específicos.

---

## Os 6 Elementos de uma Boa Spec

Uma especificação para agentes de IA precisa responder seis perguntas. Deixe qualquer uma delas em aberto e o agente a responderá por você — de formas que você não vai gostar [3][5]:

| # | Elemento | Descrição | Exemplo |
| :--- | :--- | :--- | :--- |
| 1 | **Outcomes** | O que é verdade quando o trabalho está feito | "Pedido é persistido, evento publicado, email enviado" |
| 2 | **Scope Boundaries** | O que está dentro E explicitamente fora | "OAuth está fora de escopo para esta tarefa" |
| 3 | **Constraints** | Decisões técnicas, limites de API, requisitos de performance | "Latência P99 < 200ms; usar PostgreSQL existente" |
| 4 | **Prior Decisions** | Decisões já tomadas que o agente NÃO deve questionar | "Schema do banco já definido; usar biblioteca X para criptografia" |
| 5 | **Task Breakdown** | Decomposição em sub-tarefas discretas | "1. Repository → 2. Service → 3. Controller → 4. Testes" |
| 6 | **Verification Criteria** | Como validar que está correto | "Testes passam; contrato OpenAPI validado; cobertura > 80%" |

---

## SDD vs Outras Metodologias

É fundamental entender onde o SDD se posiciona em relação a práticas existentes. Ele não substitui TDD ou BDD — ele opera em uma camada arquitetural diferente e se integra a ambos [1][3]:

| Dimensão | TDD | BDD | Vibe Coding | SDD |
| :--- | :--- | :--- | :--- | :--- |
| **Artefato primário** | Unit tests | Cenários Given/When/Then | Prompts em linguagem natural | Especificações executáveis |
| **Escopo** | Correção de função individual | Comportamento cross-funcional | Geração de aplicação completa | Contratos arquiteturais system-wide |
| **Mecanismo de validação** | Suítes de teste automatizadas | Documentação referenciada por humanos | Revisão manual (se houver) | Build falha em divergência da spec |
| **Governança de IA** | Nenhuma built-in | Nenhuma built-in | Nenhuma built-in | Constraints constitucionais e checkpoints |
| **Onde a verdade vive** | Suíte de testes | Artefatos de workshop | Histórico de prompts | Especificação versionada |

---

## Estrutura de Pastas para SDD

A organização de arquivos é parte integral da prática. O GitHub Spec-Kit [4] estabelece uma estrutura canônica que pode ser adaptada para qualquer projeto:

```
meu-projeto/
├── .specify/                          # Diretório raiz do SDD
│   ├── templates/                     # Templates core
│   │   └── overrides/                 # Overrides locais do projeto
│   ├── extensions/                    # Extensões (novos comandos)
│   │   └── templates/
│   └── presets/                       # Presets (customizações de terminologia)
│       └── templates/
├── specs/                             # Especificações do projeto
│   ├── constitution.md                # Princípios governantes (imutáveis)
│   ├── features/                      # Specs por feature
│   │   ├── auth-flow.md              # Spec funcional: fluxo de autenticação
│   │   ├── order-processing.md       # Spec funcional: processamento de pedidos
│   │   └── notification-system.md    # Spec funcional: sistema de notificações
│   ├── plans/                         # Planos técnicos derivados das specs
│   │   ├── auth-flow.plan.md
│   │   ├── order-processing.plan.md
│   │   └── notification-system.plan.md
│   └── tasks/                         # Tarefas atômicas derivadas dos planos
│       ├── auth-flow.tasks.md
│       ├── order-processing.tasks.md
│       └── notification-system.tasks.md
├── AGENTS.md                          # Instruções para agentes de IA
├── src/                               # Código-fonte (gerado/implementado)
└── tests/                             # Testes (derivados dos verification criteria)
```

Para projetos que utilizam o ecossistema GitHub Copilot (como o nosso `copilot-agents-setup`), a estrutura se adapta ao formato `.copilot/`:

```
meu-projeto/
├── .copilot/
│   ├── copilot-instructions.md        # Constitution (princípios governantes)
│   ├── agents/                        # Agentes especializados
│   │   ├── techlead-developer.agent.md
│   │   └── backend-developer.agent.md
│   └── prompts/
│       ├── techlead-developer.prompt.md   # Orquestração (Plan)
│       └── tasks/                         # Task Prompts (Tasks + Implement)
│           ├── backend-kafka-consumer-producer.prompt.md
│           └── backend-spring-security.prompt.md
├── docs/
│   └── exec-plans/                    # Planos de execução (Plans)
│       └── feature-x.plan.md
└── src/
```

---

## O Padrão Adversarial Agent

Um dos padrões mais subutilizados em SDD é atribuir um agente separado para verificar o trabalho, em vez de confiar no agente implementador para auto-verificação [3].

A estrutura funciona assim: um **Coordinator** decompõe a spec e delega tarefas a sub-agentes **Implementors**. Cada Implementor trabalha a partir de sua própria sub-spec. Um agente **Verifier** então verifica o output contra a spec antes de marcar o trabalho como completo. Os Implementors e o Verifier têm objetivos opostos: um otimiza para completar a tarefa, o outro para encontrar falhas.

No contexto do nosso projeto, este padrão se materializa assim:

| Papel | Agente no Projeto | Função |
| :--- | :--- | :--- |
| **Coordinator** | Tech Lead Developer | Decompõe a spec em sub-tasks, define constraints |
| **Implementor** | Backend / Frontend Developer | Executa as tasks conforme o plano |
| **Verifier** | QA Engineer | Verifica output contra a spec e critérios de aceitação |

---

## Exemplo Prático: Da Spec ao Código

Considere o cenário: "Implementar consumer Kafka para processar eventos de pagamento confirmado".

### Passo 1: Specify (Constitution + Feature Spec)

```markdown
# Feature: Payment Confirmed Consumer

## Outcome
Quando um evento `payment.confirmed` é publicado no tópico `payments-events`,
o serviço order-service atualiza o status do pedido para PAID e dispara
o evento `order.ready-to-fulfill` no tópico `orders-events`.

## Scope
- IN: Consumer Kafka, atualização de status, publicação de evento derivado
- OUT: Retry infinito, compensação financeira, notificação ao cliente

## Constraints
- Spring Boot 3.x + Spring Kafka
- Idempotência via chave de deduplicação (paymentId + orderId)
- DLQ após 3 retries com backoff exponencial
- Transação: consumer + producer na mesma transação Kafka

## Prior Decisions
- Schema Registry com Avro (já configurado)
- Tópico DLQ: `payments-events.order-service.dlq`

## Task Breakdown
1. DTO/Avro schema do evento de entrada
2. Consumer com @KafkaListener
3. Service de processamento com idempotência
4. Producer do evento derivado
5. Configuração de DLQ e retry
6. Testes com Testcontainers

## Verification Criteria
- [ ] Consumer processa evento e atualiza status para PAID
- [ ] Evento duplicado é ignorado (idempotência)
- [ ] Após 3 falhas, mensagem vai para DLQ
- [ ] Evento `order.ready-to-fulfill` é publicado na mesma transação
- [ ] Testes de integração passam com Kafka embarcado
```

### Passo 2: Plan (Decisões Técnicas)

O agente Tech Lead analisa a spec e gera o plano técnico:

```markdown
# Plan: Payment Confirmed Consumer

## Stack
- Spring Kafka 3.1.x com ConcurrentKafkaListenerContainerFactory
- Confluent Schema Registry (Avro)
- Spring Retry com ExponentialBackOffPolicy
- Testcontainers (kafka + schema-registry)

## Arquitetura
PaymentConfirmedEvent (Avro)
  → @KafkaListener (PaymentConfirmedConsumer)
    → PaymentProcessingService.process(event)
      → OrderRepository.updateStatus(orderId, PAID)
      → OrderEventProducer.publish(OrderReadyToFulfillEvent)

## Decisões
- Consumer group: `order-service-payment-consumer`
- Concurrency: 3 partições
- Ack mode: RECORD (commit por mensagem)
- Transactional: KafkaTransactionManager compartilhado
```

### Passo 3: Tasks (Decomposição Atômica)

```markdown
- [x] Task 1: Criar AvroSchema `PaymentConfirmedEvent` e gerar classes
- [x] Task 2: Implementar `PaymentConfirmedConsumer` com @KafkaListener
- [x] Task 3: Implementar `PaymentProcessingService` com deduplicação
- [x] Task 4: Implementar `OrderEventProducer` transacional
- [x] Task 5: Configurar DLQ com `DefaultErrorHandler` + `DeadLetterPublishingRecoverer`
- [x] Task 6: Testes de integração com `@EmbeddedKafka` ou Testcontainers
```

### Passo 4: Implement (Execução pelo Agente)

O agente Backend Developer executa cada task sequencialmente, usando Serena MCP para verificar padrões existentes no repositório antes de implementar, e apresentando o código para aprovação humana entre cada passo.

---

## SDD no Dia a Dia: Dicas Práticas

A Red Hat propõe uma abordagem pragmática para adoção gradual [6]. Em vez de reescrever todo o processo de desenvolvimento, comece com estas práticas:

**Separe o "what" do "how"**. Escreva a spec funcional (o que o software faz) em linguagem natural, sem mencionar tecnologias. Depois, em documento separado, defina as constraints técnicas (stack, arquitetura, padrões). Isso permite reusar a mesma spec funcional em diferentes linguagens ou frameworks.

**Use o agente para "vibe spec-ing"**. Antes de formalizar, faça um brainstorming iterativo com o agente para elaborar a spec. É como um jam session para delinear a música antes de gravar. Um modelo de linguagem generalista funciona bem aqui [6].

**Mantenha um LessonsLearned.md**. Quando o agente comete erros durante a implementação, registre o erro e a correção. Na próxima geração, o agente consulta esse arquivo para evitar repetir os mesmos erros — um feedback loop que reduz erros ao longo do tempo [6].

**Comece pelo Spec-First, evolua para Spec-Anchored**. Não tente implementar Spec-as-Source de imediato. Comece escrevendo specs antes de implementar e, conforme a equipe amadurece, adicione gates de validação automatizados [2].

---

## Ferramentas do Ecossistema

O ecossistema de ferramentas para SDD amadureceu significativamente entre 2025 e 2026:

| Ferramenta | Tipo | Descrição | Integração |
| :--- | :--- | :--- | :--- |
| **GitHub Spec-Kit** [4] | CLI + Templates | Toolkit open source com workflow completo (constitution → specify → plan → tasks → implement) | 30+ agentes (Copilot, Claude, Cursor, etc.) |
| **Kiro** [7] | IDE dedicada | IDE da AWS com specs como artefatos de primeira classe e tracking de implementação | Nativo |
| **Specify CLI** | CLI | Ferramenta de linha de comando do Spec-Kit para inicializar e gerenciar projetos SDD | Via `uv tool install` |
| **Copilot Agent Mode** | IDE plugin | Agentes customizados com task prompts que funcionam como mini-specs | JetBrains, VS Code |

---

## Relação com o Projeto copilot-agents-setup

O conceito de SDD já está materializado no nosso ecossistema de agentes, mesmo que com nomenclatura diferente. A tabela abaixo mapeia os conceitos SDD para os artefatos do projeto:

| Conceito SDD | Artefato no Projeto | Exemplo |
| :--- | :--- | :--- |
| **Constitution** | `copilot-instructions.md` | Princípios globais, stack, padrões de código |
| **Feature Spec** | Task Prompts (`.prompt.md`) | `backend-kafka-consumer-producer.prompt.md` |
| **Plan** | `docs/exec-plans/` | Plano de execução gerado pelo Tech Lead |
| **Tasks** | Steps dentro do Task Prompt | "Step 1: Crie o Consumer... Step 2: Implemente o Service..." |
| **Implement** | Execução pelo agente com human-in-the-loop | Agente executa, pausa, aguarda aprovação |
| **Verify** | QA Engineer + testes | `qa-contract-testing.prompt.md` |
| **Coordinator** | Tech Lead Developer | Decompõe, especifica, delega via handoff |
| **Verifier** | QA Engineer | Verifica contra critérios de aceitação |

---

## Anti-Padrões a Evitar

O ThoughtWorks Technology Radar alerta explicitamente sobre armadilhas na adoção de SDD [2]:

| Anti-Padrão | Problema | Solução |
| :--- | :--- | :--- |
| **Big-bang specification** | Spec gigante escrita upfront que nunca é atualizada | Specs incrementais por feature, evoluindo com o código |
| **Spec como burocracia** | Spec existe mas ninguém a consulta ou atualiza | Spec-Anchored com testes que falham em divergência |
| **Over-specification** | Spec tão detalhada que é mais complexa que o código | Foco em "what" e constraints, não em "how" |
| **Under-specification** | Spec vaga que não elimina ambiguidade | Usar os 6 elementos obrigatórios como checklist |
| **Spec sem verification** | Spec define o que fazer mas não como validar | Sempre incluir critérios de verificação executáveis |

---

## Conclusão

Spec-Driven Development não é uma revolução — é uma evolução natural. As práticas de BDD (Given/When/Then), Design by Contract (preconditions/postconditions) e API-First (OpenAPI antes do código) já pavimentaram o caminho. O que mudou é que agentes autônomos de IA agora podem **consumir e executar** essas especificações de forma confiável, transformando documentos passivos em contratos executáveis.

O curso "Spec-Driven Development with Coding Agents" da DeepLearning.AI em parceria com a JetBrains [8] resume a proposta de valor: "Vibe coding é rápido, mas frequentemente produz código que não corresponde ao que você pediu. Spec-driven development é a alternativa disciplinada: escreva uma spec clara em markdown definindo o que construir, e deixe seu coding agent implementá-la."

Para equipes que já utilizam agentes autônomos — como é o caso do nosso ecossistema com GitHub Copilot Agent Mode — a adoção de SDD é o próximo passo natural para escalar a autonomia sem sacrificar a previsibilidade.

---

## Referências

[1] Piskala, D. B. "Spec-Driven Development: From Code to Contract in the Age of AI Coding Assistants." arXiv:2602.00180, Fevereiro 2026.

[2] ThoughtWorks. "Technology Radar Vol. 33 — Spec-Driven Development." Novembro 2025. Disponível em: https://www.thoughtworks.com/radar/techniques/spec-driven-development

[3] Shah, M. "What Is Spec-Driven Development? A Complete Guide." Augment Code, Abril 2026. Disponível em: https://www.augmentcode.com/guides/what-is-spec-driven-development

[4] GitHub. "Spec-Kit: An open source toolkit for Spec-Driven Development." 2026. Disponível em: https://github.com/github/spec-kit

[5] Osmani, A. "How to write a good spec for AI agents." Janeiro 2026. Disponível em: https://addyosmani.com/blog/good-spec/

[6] Naszcyniec, R. "How spec-driven development improves AI coding quality." Red Hat Developers, Outubro 2025. Disponível em: https://developers.redhat.com/articles/2025/10/22/how-spec-driven-development-improves-ai-coding-quality

[7] AWS. "Kiro: Move beyond AI coding to agentic engineering." 2025. Disponível em: https://kiro.dev/

[8] DeepLearning.AI + JetBrains. "Spec-Driven Development with Coding Agents." 2026. Disponível em: https://www.deeplearning.ai/courses/spec-driven-development-with-coding-agents
