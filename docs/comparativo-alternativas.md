# Análise Comparativa: Solução Proposta vs Alternativas de Mercado

Este documento apresenta uma análise técnica detalhada comparando a solução de RAG local implementada neste projeto (`mcp-vector-search` + Ollama + LanceDB) com ferramentas consolidadas de inteligência de código. A avaliação considera os requisitos específicos do ambiente alvo: Windows 11, ausência de privilégios administrativos e restrição ao uso de Docker.

## 1. Avaliação de Ferramentas de Code Search e RAG

### Sourcebot
O [Sourcebot](https://github.com/sourcebot-dev/sourcebot) [1] combina a velocidade da busca por expressões regulares (Zoekt [2]) com capacidades de IA.
Apesar de poderoso, apresenta barreiras intransponíveis para este projeto:
1. **Dependência do Docker**: O *deploy* exige Docker Compose [3], inviabilizando o uso em ambientes corporativos restritos.
2. **Monetização do MCP**: A integração via *Model Context Protocol* (MCP) não está disponível na versão gratuita. É necessário assinar o plano Pro ($20/usuário/mês) [4].
3. **Consumo de Recursos**: Exige no mínimo 4 GB de RAM dedicados apenas para os contêineres [3].

### Continue.dev + nomic-embed-text
O [Continue.dev](https://docs.continue.dev/) [5] é uma extensão open-source para VS Code e JetBrains. Ele suporta a conexão de servidores MCP [6] e possui integração nativa com o [Ollama](https://ollama.com/) [7], recomendando oficialmente o modelo `nomic-embed-text` para a geração de *embeddings* locais de alta performance [8].
**Limitação para o projeto:** O Continue.dev atua como um **concorrente** e substituto direto para a interface do GitHub Copilot Chat. Como a premissa do projeto é utilizar a documentação e o ecossistema oficial do GitHub Copilot (Agent Mode), adotá-lo fugiria do escopo. Além disso, o projeto Continue.dev parece estar passando por instabilidades na comunidade (com *issues* reportando problemas de indexação em bases grandes) [9].

### Greptile
O [Greptile](https://www.greptile.com/) [10] é uma plataforma focada em revisão de código em *Pull Requests* via IA. Ele disponibiliza um servidor MCP [11], mas é um serviço comercial pago ($30 por desenvolvedor/mês) [12] focado em CI/CD, e não um índice vetorial local leve para tempo de desenvolvimento.

## 2. Avaliação de Ferramentas Auxiliares e Servidores MCP

A arquitetura do GitHub Copilot permite a extensão de suas capacidades conectando servidores MCP complementares. Abaixo analisamos opções que podem atuar em conjunto ou no lugar do `mcp-vector-search`.

### Serena MCP
O [Serena](https://github.com/oraios/serena) [13] é um *toolkit* MCP patrocinado pela Microsoft que fornece ferramentas semânticas de recuperação e edição de código.
Diferente da nossa solução baseada em RAG (busca vetorial por similaridade), o Serena opera no nível de símbolo utilizando o *Language Server Protocol* (LSP). Ele é excelente para tarefas determinísticas como encontrar declarações, referências e refatorações (ex: *rename symbol*).
**Recomendação:** O Serena é **altamente complementar** à nossa solução RAG. Enquanto o RAG local encontra conceitos baseados em linguagem natural (ex: "onde a senha é validada?"), o Serena permite que o Copilot navegue pela árvore de dependências (ex: "quem chama este método?"). Ele pode ser instalado localmente via `uv` sem necessidade de Docker ou privilégios de administrador.

### Filesystem MCP
O [Filesystem MCP Server](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem) [14] é uma implementação oficial que permite leitura e escrita segura de arquivos locais, controlada por listas de permissão (*whitelists*).
**Recomendação:** É útil para dar ao Copilot acesso de escrita ao *workspace*, mas **não realiza buscas semânticas ou textuais**. Serve como uma ferramenta auxiliar básica, não substituindo o motor de RAG.

### Roo Code (Descontinuado)
O [Roo Code](https://github.com/RooCodeInc/Roo-Code) [15] foi uma extensão open-source popular (fork do Cline) que suportava nativamente servidores MCP e múltiplos *providers* (incluindo Ollama).
**Limitação:** O projeto foi oficialmente **descontinuado e arquivado** em 15 de maio de 2026. A comunidade migrou para alternativas como ZooCode e o próprio Cline original [16]. Portanto, não é uma opção viável para adoção futura.

### Ollama (Standalone)
O [Ollama](https://ollama.com/) [7] é a peça central da nossa arquitetura para manter a privacidade. Ele pode ser instalado em *user-level* no Windows (sem admin) e gerencia modelos de linguagem e *embeddings*.
Para código, o modelo `nomic-embed-text` [17] provou-se extremamente eficiente, suportando um contexto de 8192 *tokens* e superando modelos comerciais como o `text-embedding-ada-002` da OpenAI em benchmarks [18].

## 3. Matriz Comparativa

A tabela abaixo sintetiza como a solução construída neste repositório se compara com as principais alternativas de mercado, considerando as restrições impostas.

| Critério | Solução Proposta (Este Repositório) | Sourcebot | Continue.dev | Serena MCP |
| :--- | :--- | :--- | :--- | :--- |
| **Abordagem** | RAG Vetorial (Similaridade) | Busca Trigram/Regex | RAG Vetorial | AST / LSP (Símbolos) |
| **Integração Copilot** | Nativa (via MCP) | Requer Plano Pago | Incompatível | Nativa (via MCP) |
| **Requer Docker?** | Não | Sim (Obrigatório) | Não | Não |
| **Requer Admin?** | Não | Sim (para Docker) | Não | Não |
| **Custo** | 100% Gratuito | $20/mês para MCP | Gratuito | Gratuito (com plugin pago opcional) |
| **Foco Principal** | Busca semântica local via IDE | Busca corporativa escalável | Substituir o Copilot | Navegação e Refatoração Semântica |

## 4. Conclusão e Recomendação

A arquitetura implementada no **Copilot Agents Local Setup** (`mcp-vector-search` + Ollama + `nomic-embed-text` + LanceDB) é a mais aderente aos requisitos estritos de um ambiente Windows 11 corporativo (sem Docker, sem privilégios administrativos e utilizando ferramentas gratuitas).

Enquanto o **Sourcebot** falha em atender desenvolvedores individuais com máquinas restritas devido à dependência do Docker e ao bloqueio do servidor MCP por *paywall*, o **Continue.dev** foge do escopo por competir diretamente com o GitHub Copilot.

A **combinação ideal** para o cenário proposto é utilizar a nossa solução de RAG Vetorial para a busca de contexto em linguagem natural, operando **em conjunto** com o **Serena MCP**, que adiciona capacidades de navegação estrutural determinística (LSP). Ambos funcionam localmente, são gratuitos, respeitam as políticas de restrição (sem Docker/Admin) e se integram perfeitamente ao ecossistema oficial do GitHub Copilot através do protocolo MCP.

## Referências

[1] Sourcebot Repository. GitHub. Disponível em: https://github.com/sourcebot-dev/sourcebot
[2] Zoekt Repository. GitHub. Disponível em: https://github.com/sourcegraph/zoekt
[3] Docker Compose Deployment. Sourcebot Documentation. Disponível em: https://docs.sourcebot.dev/docs/deployment/docker-compose
[4] Sourcebot Pricing. Disponível em: https://www.sourcebot.dev/pricing
[5] Continue.dev Documentation. Disponível em: https://docs.continue.dev/
[6] Model Context Protocol in Continue. Disponível em: https://docs.continue.dev/customize/deep-dives/mcp
[7] Ollama Official Website. Disponível em: https://ollama.com/
[8] Embed Role - Continue.dev. Disponível em: https://docs.continue.dev/customize/model-roles/embeddings
[9] Continue.dev GitHub Issues. Disponível em: https://github.com/continuedev/continue/issues
[10] Greptile Official Website. Disponível em: https://www.greptile.com/
[11] Greptile MCP Server Overview. Disponível em: https://www.greptile.com/docs/mcp/overview
[12] Greptile Pricing. Disponível em: https://www.greptile.com/pricing
[13] Serena MCP Repository. GitHub. Disponível em: https://github.com/oraios/serena
[14] Filesystem MCP Server. GitHub. Disponível em: https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem
[15] Roo Code Repository. GitHub. Disponível em: https://github.com/RooCodeInc/Roo-Code
[16] Roo Code Discontinuation Notice. GitHub. Disponível em: https://github.com/RooCodeInc/Roo-Code#disclaimer
[17] Nomic Embed Text Model. Ollama Library. Disponível em: https://ollama.com/library/nomic-embed-text
[18] Papers Explained: Nomic Embed. Medium. Disponível em: https://ritvik19.medium.com/papers-explained-110-nomic-embed-8ccae819dac2
