# Model Context Protocol (MCP): O Padrão Universal para Agentes Autônomos

A transição de assistentes baseados em chat para agentes autônomos de desenvolvimento esbarrou, durante muito tempo, no problema da fragmentação. Para que uma inteligência artificial interagisse com o mundo real, era necessário construir conectores proprietários para cada ferramenta, banco de dados ou API. Esse cenário gerava um esforço de integração de ordem $N \times M$ (onde $N$ são as aplicações de IA e $M$ são as ferramentas), tornando ecossistemas corporativos frágeis e difíceis de manter [1].

Em novembro de 2024, a Anthropic introduziu o **Model Context Protocol (MCP)** para resolver esse gargalo, e em dezembro de 2025, o protocolo foi doado à Agentic AI Foundation, sob a chancela da Linux Foundation [1]. Hoje, com suporte nativo de gigantes como OpenAI, Google DeepMind, Microsoft e GitHub, o MCP consolidou-se como o "USB-C" da inteligência artificial: um padrão aberto e neutro que permite conectar qualquer modelo de linguagem a qualquer fonte de dados ou sistema de execução de forma padronizada e segura [2].

Este documento explora a arquitetura do MCP, suas primitivas fundamentais, mecanismos de transporte, ciclo de vida e aplicações práticas na engenharia de *harness* para agentes autônomos.

---

## 1. Arquitetura Client-Host-Server

A especificação do MCP baseia-se em uma arquitetura de três camadas, utilizando o formato leve de mensagens JSON-RPC 2.0. Essa estrutura isola as responsabilidades e mantém fronteiras claras de segurança [3].

| Componente | Papel na Arquitetura | Exemplo Prático |
| :--- | :--- | :--- |
| **Host** | O aplicativo ou ambiente com o qual o usuário interage. Gerencia as instâncias de clientes, aplica políticas de segurança e controla a orquestração do modelo de linguagem. | GitHub Copilot Agent Mode, Cursor, Claude Desktop, Compozy. |
| **Client** | O conector que reside dentro do *Host*. Mantém uma relação de um-para-um com um servidor específico, gerenciando o estado da sessão e o roteamento de mensagens. | O motor interno do VS Code que negocia com o servidor local. |
| **Server** | O provedor independente de contexto e capacidades. Pode ser um processo local ou um serviço remoto que executa as ferramentas solicitadas pelo modelo. | Serena MCP (para navegação LSP), mcp-vector-search (para RAG). |

A principal vantagem desse *design* é a **composabilidade**. Um único *Host* (como o IntelliJ com o plugin do Copilot) pode orquestrar múltiplos *Clients*, conectando-se simultaneamente a um servidor MCP que lê arquivos locais e a outro servidor remoto que consulta chamadas de API no Datadog, sem que esses servidores enxerguem o tráfego um do outro [3].

---

## 2. As Três Primitivas do MCP

Servidores MCP expõem suas capacidades através de três primitivas fundamentais, cada uma com um modelo de interação distinto [4].

### Tools (Ferramentas)
As ferramentas representam a capacidade de **ação** do agente. Elas são funções tipadas (validadas via JSON Schema) que o modelo de linguagem decide quando e como invocar. Ferramentas podem alterar o estado do sistema, como escrever em um banco de dados, compilar código ou criar uma *branch* no Git [4].

Para gerenciar o risco inerente à execução autônoma, a especificação introduziu o conceito de **Tool Annotations** (Anotações de Ferramenta). Essas anotações funcionam como um vocabulário de risco, fornecendo dicas (*hints*) ao cliente [5]:

- `readOnlyHint`: Indica se a ferramenta modifica o ambiente (o padrão é assumir que modifica).
- `destructiveHint`: Indica se a modificação é destrutiva, exigindo maior cautela.
- `idempotentHint`: Indica se é seguro chamar a ferramenta repetidas vezes com os mesmos argumentos.
- `openWorldHint`: Indica se a ferramenta interage com sistemas externos além da máquina local.

Como servidores não confiáveis podem mentir sobre essas anotações, a especificação obriga os clientes a tratá-las de forma pessimista até que a confiança no servidor seja estabelecida [5].

### Resources (Recursos)
Os recursos fornecem **dados de leitura** passivos. Eles expõem informações estruturadas — como arquivos, esquemas de banco de dados ou logs — para que a aplicação (o *Host*) decida como utilizá-las [4]. 

Os recursos são identificados por URIs exclusivas e podem ser estáticos (ex: `file:///workspace/README.md`) ou dinâmicos, utilizando *Resource Templates* (ex: `github://repo/{owner}/{repo}/issues`). Diferente das ferramentas, os recursos são controlados pela aplicação e não pelo modelo, permitindo interfaces ricas de seleção por parte do usuário [4].

### Prompts (Templates de Instrução)
Os *prompts* são modelos de instrução reutilizáveis que orientam o modelo a utilizar ferramentas e recursos específicos de forma padronizada. Eles são controlados pelo usuário, geralmente invocados por comandos rápidos (como `/mcp.serena.analyze_architecture` no Copilot Chat) [4].

---

## 3. Transporte e Ciclo de Vida

O MCP não dita a linguagem de programação do servidor (existem SDKs robustos em TypeScript, Python e Go), mas define rigorosamente como os dados trafegam e como a sessão é mantida [6].

### Mecanismos de Transporte

A especificação atual (a partir de 2025-03-26) suporta dois transportes oficiais [6]:

1. **STDIO (Standard Input/Output):** O cliente inicia o servidor MCP como um subprocesso local. A comunicação ocorre lendo do `stdin` e escrevendo no `stdout`, com mensagens JSON-RPC delimitadas por quebra de linha. É o transporte ideal para desenvolvimento de código, onde a latência precisa ser mínima e o acesso ao disco local é necessário [6].
2. **Streamable HTTP:** Substituiu o antigo protocolo HTTP+SSE. Projetado para servidores remotos, utiliza requisições HTTP POST e GET com *Server-Sent Events* (SSE) para respostas em *streaming*. Esse transporte permite implantações corporativas escaláveis, com suporte a múltiplos clientes, balanceamento de carga e reconexão através do cabeçalho `Last-Event-ID` [6].

### O Ciclo de Vida da Sessão

Toda conexão MCP passa por um ciclo de vida determinístico [7]:

1. **Inicialização (Handshake):** O cliente envia um `initialize` informando a versão do protocolo e suas capacidades (ex: suporte a *sampling*). O servidor responde com suas próprias capacidades (ex: suporte a ferramentas e recursos). O cliente confirma com um `initialized`.
2. **Operação:** Ocorre a troca de mensagens baseada nas capacidades negociadas.
3. **Encerramento:** Para o transporte STDIO, o cliente fecha o fluxo de entrada e aguarda o término do processo. Para HTTP, as conexões são encerradas.

---

## 4. Evolução: De Execução Síncrona à Colaboração Ativa

As versões mais recentes da especificação do MCP transformaram o protocolo de um simples executor de comandos para um *framework* de colaboração avançada entre agentes e ferramentas [1].

### Tasks (Tarefas Assíncronas)
Antes das *Tasks*, o MCP era estritamente síncrono, o que causava problemas com operações longas (como uma migração de banco de dados). O padrão *call-now, fetch-later* permite que o servidor retorne um identificador imediatamente, enquanto o trabalho continua em segundo plano, reportando seu progresso através de estados como `working` ou `input_required` [1].

### Sampling e Elicitation
O fluxo tradicional dita que o modelo comanda e o servidor obedece. Com o **Sampling**, o servidor pode inverter esse fluxo e solicitar que o modelo de linguagem do *Host* raciocine sobre um estado intermediário antes de prosseguir. Com a **Elicitation**, o servidor pode pausar a execução e pedir dados ao usuário humano (através de um formulário ou de um redirecionamento seguro para uma URL de autenticação) [1].

### MCP Apps (Camada de Interface)
Lançado em janeiro de 2026, o *MCP Apps* estende o protocolo para além do texto. Ferramentas agora podem retornar interfaces HTML ricas que são renderizadas em *iframes* isolados dentro do chat. Isso permite que agentes não apenas descrevam uma alteração no banco de dados, mas apresentem um *dashboard* interativo com os resultados [1].

---

## 5. Implementação no Ecossistema Copilot e IntelliJ

A integração do MCP em ambientes de desenvolvimento corporativos (como IntelliJ e VS Code) mudou a forma como engenheiros de software trabalham. A configuração é declarativa e descentralizada.

No VS Code e no IntelliJ, os servidores MCP são configurados no arquivo `mcp.json` (geralmente na pasta `.vscode/` do projeto ou globalmente no perfil do usuário) [8].

```json
{
  "servers": {
    "serena": {
      "command": "uvx",
      "args": ["serena-mcp"]
    },
    "jira-remote": {
      "type": "http",
      "url": "https://mcp.empresa.com/jira"
    }
  }
}
```

Neste projeto (*Copilot Agents Local Setup*), utilizamos essa capacidade para integrar o **Serena MCP** (navegação determinística via *Language Server Protocol*) e o **mcp-vector-search** (busca semântica via RAG local). Quando o agente "TechLead" é invocado, ele utiliza o conhecimento agnóstico do seu *prompt* para acionar as ferramentas que o IntelliJ disponibiliza através desses servidores MCP locais.

---

## 6. Conclusão

O Model Context Protocol não é apenas mais uma API. Ele representa a fundação da interoperabilidade na era da inteligência artificial agentiva. Ao padronizar como modelos descobrem, invocam e interagem com ferramentas externas, o MCP reduz o custo de integração, mitiga o risco de *vendor lock-in* e permite a construção de ecossistemas corporativos onde o conhecimento (o modelo) e a capacidade de ação (o servidor MCP) evoluem de forma independente e segura.

---

## Referências

[1] M. Paktiti, "Everything your team needs to know about MCP in 2026," WorkOS, Mar. 26, 2026. [Online]. Available: https://workos.com/blog/everything-your-team-needs-to-know-about-mcp-in-2026.
[2] "What is the Model Context Protocol (MCP)?," Model Context Protocol, 2025. [Online]. Available: https://modelcontextprotocol.io/docs/getting-started/intro.
[3] "Architecture," Model Context Protocol, Jun. 18, 2025. [Online]. Available: https://modelcontextprotocol.io/specification/2025-06-18/architecture.
[4] "Understanding MCP servers," Model Context Protocol, 2025. [Online]. Available: https://modelcontextprotocol.io/docs/learn/server-concepts.
[5] O. Hungerford, S. Morrow, and L. Chang, "Tool Annotations as Risk Vocabulary: What Hints Can and Can't Do," Model Context Protocol Blog, Mar. 16, 2026. [Online]. Available: https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/.
[6] "Transports," Model Context Protocol, Mar. 26, 2025. [Online]. Available: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports.
[7] "Lifecycle," Model Context Protocol, Nov. 25, 2025. [Online]. Available: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle.
[8] "Add and manage MCP servers in VS Code," Visual Studio Code Docs, 2026. [Online]. Available: https://code.visualstudio.com/docs/agent-customization/mcp-servers.
