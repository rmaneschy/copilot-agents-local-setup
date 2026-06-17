# Análise Comparativa: Solução Proposta vs Alternativas de Mercado

Este documento apresenta uma análise técnica detalhada comparando a solução de RAG local implementada neste projeto (`mcp-vector-search` + Ollama + LanceDB) com ferramentas consolidadas de inteligência de código, com destaque para o **Sourcebot**, **Continue.dev** e **Greptile**. A avaliação considera os requisitos específicos do ambiente alvo: Windows 11, ausência de privilégios administrativos e restrição ao uso de Docker.

## 1. Avaliação do Sourcebot

O [Sourcebot](https://github.com/sourcebot-dev/sourcebot) [1] é uma ferramenta de busca e compreensão de código *self-hosted* que ganhou grande tração como uma alternativa de código aberto. Ele combina a velocidade da busca por expressões regulares (usando o motor Zoekt [2]) com capacidades de IA.

### Limitações Críticas para o Cenário Atual

Apesar de ser uma ferramenta poderosa, o Sourcebot apresenta barreiras intransponíveis para o contexto deste projeto:

1. **Dependência Obrigatória do Docker**: O *deploy* do Sourcebot exige o uso do Docker Compose [3]. Em ambientes corporativos restritos onde o Docker não está disponível ou onde o usuário não possui privilégios de administrador para instalá-lo, o Sourcebot não pode ser executado localmente.
2. **Monetização do Servidor MCP**: A funcionalidade de integração via *Model Context Protocol* (MCP) não está disponível na versão gratuita (Community). Para utilizar o servidor MCP do Sourcebot e conectá-lo ao GitHub Copilot Chat, é necessário assinar o plano Pro, que custa $20 por usuário ao mês [4]. A versão gratuita limita-se à busca textual e exploração de arquivos via interface web.
3. **Consumo de Recursos**: A arquitetura do Sourcebot, desenhada para indexar milhares de repositórios simultaneamente, exige no mínimo 4 GB de RAM dedicados apenas para os contêineres da aplicação [3], sem contabilizar o processamento do modelo de linguagem.

## 2. Avaliação de Outras Alternativas

### Continue.dev

O [Continue.dev](https://docs.continue.dev/) [5] é uma extensão de código aberto para VS Code e JetBrains que permite a criação de assistentes de IA customizados. Ele possui integração nativa com o Ollama [6] e suporta a conexão de servidores MCP [7].

**Por que não adotar o Continue.dev isoladamente?**
O Continue.dev é um substituto direto para a interface do GitHub Copilot Chat, e não apenas um motor de indexação. Como a premissa do projeto é **utilizar a documentação e as ferramentas oficiais do GitHub Copilot** (especificamente o Copilot Agent Mode), substituir o cliente do Copilot pelo Continue.dev fugiria do escopo. No entanto, a arquitetura RAG local que implementamos (Python + LanceDB + Ollama) é muito semelhante à abordagem de RAG customizado sugerida pela própria documentação do Continue.dev [8].

### Greptile

O [Greptile](https://www.greptile.com/) [9] é uma plataforma voltada principalmente para a revisão de código em *Pull Requests* via IA. Ele também disponibiliza um servidor MCP [10].

**Por que não adotar o Greptile?**
O Greptile é um serviço comercial pago ($30 por desenvolvedor/mês) [11] e, embora ofereça opções de *self-hosting*, seu foco principal é atuar na esteira de CI/CD para revisões de código, e não como um índice vetorial local leve para desenvolvedores em tempo de desenvolvimento.

### Bloop e Zoekt

O **Bloop** era uma promessa interessante de busca semântica em Rust que não dependia de Docker, porém o projeto parece não estar mais ativamente mantido. Já o **Zoekt** [2] é extremamente eficiente para buscas textuais (usando trigramas), mas não possui capacidades nativas de busca semântica vetorial (RAG) nem integração padronizada via MCP.

## 3. Matriz Comparativa

A tabela abaixo sintetiza como a solução construída neste repositório se compara com as principais alternativas de mercado, considerando as restrições impostas.

| Critério | Solução Proposta (Este Repositório) | Sourcebot | Continue.dev | Greptile |
| :--- | :--- | :--- | :--- | :--- |
| **Integração Copilot** | Nativa (via MCP) | Requer Plano Pago | Incompatível (Concorrente) | Sim (via MCP) |
| **Requer Docker?** | Não | Sim | Não | Sim (Self-hosted) |
| **Requer Admin?** | Não (Ollama e Python instalam em *User-level*) | Sim (para instalar Docker) | Não | Sim |
| **Custo** | 100% Gratuito | $20/mês para MCP | Gratuito | $30/mês |
| **Foco Principal** | Busca semântica local via IDE | Busca corporativa escalável | Substituir o Copilot | Revisão de PRs |
| **Armazenamento** | Vetorial (LanceDB *serverless*) | Zoekt + Vetores | LanceDB (Opcional) | Nuvem ou K8s |
| **Privacidade** | 100% Local (Ollama) | Local (BYOK) | Local ou Nuvem | Nuvem |

## 4. Conclusão e Recomendação

A arquitetura implementada no **Copilot Agents Local Setup** é a mais aderente aos requisitos estritos de um ambiente Windows 11 corporativo (sem Docker, sem privilégios administrativos e utilizando ferramentas gratuitas).

Enquanto o **Sourcebot** se destaca como uma excelente plataforma para times que possuem infraestrutura dedicada (Kubernetes ou Docker Swarm) e orçamento para o plano Pro, ele falha em atender desenvolvedores individuais com máquinas restritas devido à dependência do Docker e ao bloqueio do servidor MCP por *paywall*. 

A solução desenvolvida com `mcp-vector-search`, Ollama e LanceDB garante que o processamento de *embeddings* ocorra localmente sem atrito com políticas de TI, integrando-se perfeitamente ao ecossistema oficial do GitHub Copilot através do protocolo MCP.

## Referências

[1] Sourcebot Repository. GitHub. Disponível em: https://github.com/sourcebot-dev/sourcebot
[2] Zoekt Repository. GitHub. Disponível em: https://github.com/sourcegraph/zoekt
[3] Docker Compose Deployment. Sourcebot Documentation. Disponível em: https://docs.sourcebot.dev/docs/deployment/docker-compose
[4] Sourcebot Pricing. Disponível em: https://www.sourcebot.dev/pricing
[5] Continue.dev Documentation. Disponível em: https://docs.continue.dev/
[6] Using Ollama with Continue. Disponível em: https://docs.continue.dev/guides/ollama-guide
[7] Model Context Protocol in Continue. Disponível em: https://docs.continue.dev/customize/deep-dives/mcp
[8] How to Build Custom Code RAG. Continue.dev. Disponível em: https://docs.continue.dev/guides/custom-code-rag
[9] Greptile Official Website. Disponível em: https://www.greptile.com/
[10] Greptile MCP Server Overview. Disponível em: https://www.greptile.com/docs/mcp/overview
[11] Greptile Pricing. Disponível em: https://www.greptile.com/pricing
