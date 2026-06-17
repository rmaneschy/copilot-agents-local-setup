# Copilot Agents Local Setup

## Visão Geral do Projeto

O projeto **Copilot Agents Local Setup** fornece uma arquitetura e um conjunto de ferramentas para implementar um sistema de *Retrieval-Augmented Generation* (RAG) 100% local, voltado para a análise avançada de código-fonte. A solução foi concebida para operar em ambientes de desenvolvimento corporativos restritos, especificamente em máquinas com sistema operacional Windows 11, onde o usuário não possui privilégios de administrador e não há disponibilidade de contêineres Docker.

A integração principal ocorre com o **IntelliJ IDEA** (e opcionalmente VS Code) através do plugin **GitHub Copilot Chat**, utilizando o padrão *Model Context Protocol* (MCP). A solução combina **duas abordagens complementares**: busca semântica em linguagem natural (RAG Vetorial) e navegação estrutural determinística (Serena MCP via LSP). Isso permite que o assistente de inteligência artificial realize análises profundas em todo o diretório de trabalho (`~/workspace`), auxiliando engenheiros de software especialistas na compreensão de arquiteturas complexas, mapeamento de dependências, análise de contratos de dados e segurança entre microserviços.

## Arquitetura e Componentes da Solução

A arquitetura baseia-se na composição de ferramentas de código aberto e leves, garantindo privacidade absoluta (o código nunca sai da máquina para ser indexado) e baixo consumo de recursos do desenvolvedor.

| Componente | Função | Justificativa |
| :--- | :--- | :--- |
| **Ollama** | Motor local para modelos de linguagem e *embeddings* (ex: `nomic-embed-text`). | Permite instalação em nível de usuário no Windows (sem admin) e gera representações vetoriais do código localmente. |
| **mcp-vector-search** | Servidor MCP em Python que realiza a análise da *Abstract Syntax Tree* (AST) e a indexação do código. | Fornece *tools* de busca semântica vetorial baseada em linguagem natural. |
| **LanceDB** | Banco de dados vetorial embutido (*serverless*). | Armazena os *embeddings* em disco de forma eficiente, sem utilizar o Docker. |
| **Serena MCP** | Servidor MCP patrocinado pela Microsoft que utiliza o *Language Server Protocol* (LSP). | Fornece navegação determinística no código (find_symbol, find_references), complementando a busca vetorial. Instala-se via `uv` sem privilégios de administrador. |
| **Custom Agents** | Perfis especializados (`.github/agents/`) que direcionam o comportamento do Copilot. | Aplicam o princípio de responsabilidade única, criando "personas" (ex: Tech Lead) focadas em tarefas específicas. |
| **Prompt Files** | Arquivos de template (`.github/prompts/`) com instruções detalhadas para o Copilot. | Padronizam e facilitam a execução de tarefas recorrentes, como análise arquitetural e geração de diagramas C4. |

Para um aprofundamento técnico, consulte o documento de [Arquitetura da Solução](docs/architecture.md) e a nossa [Análise Comparativa com Alternativas de Mercado](docs/comparativo-alternativas.md) (como Sourcebot, Continue.dev e Greptile).

## Estrutura do Repositório

O repositório está organizado seguindo os princípios de responsabilidade única e separação de conceitos:

- `.github/agents/`: Definições dos agentes customizados para o Copilot (`TechLead-Architecture`, `TechLead-Communication`, `TechLead-DataContracts`, `TechLead-C4Diagram`).
- `.github/prompts/`: Arquivos de *prompt* prontos para uso no Copilot Chat.
- `.github/copilot-instructions.md`: Instruções de contexto global para o Copilot neste projeto.
- `.vscode/`: Configuração alternativa de MCP para usuários do Visual Studio Code.
- `docs/`: Documentação técnica, decisões arquiteturais e guias.
- `scripts/`: Scripts de automação (PowerShell) para configuração, indexação e monitoramento de saúde do ambiente.

## Instalação e Configuração

O processo de instalação foi automatizado por meio de scripts PowerShell, projetados para rodar sem elevação de privilégios.

### Pré-requisitos

1. **Windows 11** (sem necessidade de privilégios administrativos).
2. **Python 3.11+** (pode ser instalado via Microsoft Store).
3. **Ollama** (baixe o instalador do Windows em [ollama.com/download](https://ollama.com/download), que instala no diretório do usuário).
4. **IntelliJ IDEA** com o plugin **GitHub Copilot** (versão 1.5.57 ou superior, com Agent Mode e MCP habilitados).

### Passos para Instalação

1. Clone este repositório em sua máquina local.
2. Abra o PowerShell e navegue até a pasta do projeto.
3. Execute o script de configuração principal:

```powershell
.\scripts\setup.ps1
.\scripts\setup-serena.ps1
```

> **Atenção para usuários corporativos:** Se a sua rede utiliza um proxy com inspeção SSL/TLS, o script `setup.ps1` pode falhar no download do modelo com erro de `SHA256 digest`. Neste caso, utilize o script de contorno:
> ```powershell
> .\scripts\setup-proxy-workaround.ps1
> ```

Os scripts irão configurar o ambiente virtual Python, instalar o `mcp-vector-search`, baixar o modelo de *embedding* no Ollama, instalar o **Serena MCP** via `uv` (gerenciador de pacotes) e configurar o arquivo `mcp.json` na pasta de configuração do IntelliJ (`~/.config/github-copilot/intellij/`).

*Nota: Existe também um script de setup alternativo (`setup-alternative-node.ps1`) baseado em Node.js/Bun, caso prefira não utilizar o Ollama.*

### Indexação do Workspace

Após a configuração, é necessário indexar o código-fonte do seu diretório de trabalho:

```powershell
.\scripts\index-workspace.ps1 -Path "C:\Users\SEU_USUARIO\workspace"
```

## Utilização e Prompts Especializados

Uma vez configurado, o servidor MCP local expõe ferramentas de busca semântica para o GitHub Copilot. Você pode invocar os agentes e *prompts* diretamente no chat do IntelliJ para realizar tarefas complexas.

### 1. Análise Arquitetural de Serviço

Para analisar o fluxo de ponta a ponta de um microserviço, utilize o agente de arquitetura:

> "Ative o projeto do serviço <NOME_DO_SERVICO> com Serena.
> Analise o fluxo arquitetural de ponta a ponta: endpoints de entrada, controllers/handlers, services/use cases, repositories/DAOs, chamadas HTTP/gRPC externas, publicação ou consumo de mensagens, acesso a banco, tratamento de erro, autenticação/autorização e observabilidade.
> Use ferramentas semânticas como visão geral de símbolos, busca por símbolo e referências. Retorne uma explicação com evidências por arquivo e símbolo. Não faça alterações."

### 2. Mapeamento de Comunicação entre Microserviços

Para descobrir relações de dependência no seu *workspace*:

> "Na raiz C:\Users\SEU_USUARIO\workspace, descubra relações entre microserviços. Procure: URLs internas, nomes de serviços em variáveis de ambiente, clients Feign, WebClient, RestTemplate, Axios, fetch, gRPC, protobuf, tópicos Kafka/RabbitMQ/SQS/PubSub, consumers/producers, OpenAPI clients, Helm values, Kubernetes Service/Ingress, docker-compose service names.
> Gere uma matriz: origem | destino | protocolo | evidência | criticidade | observações. Diferencie dependência confirmada de dependência provável."

### 3. Geração de Diagramas C4

Para obter uma visão visual da arquitetura baseada em código real:

> "Gere um diagrama C4 Container da plataforma com evidências de código."

### 4. Consultas sobre Contratos e Segurança

Você pode fazer perguntas direcionadas, como:
- "Quais microserviços gravam na base de pedidos?"
- "Quais serviços dependem deste contrato OpenAPI?"
- "Onde a autenticação é validada e quais serviços ignoram autorização?"

## Monitoramento

Para verificar a saúde de todos os componentes da solução (Ollama, Python, servidor MCP e configurações), execute o script de verificação:

```powershell
.\scripts\health-check.ps1
```

## Contribuições e Padrões

Este projeto segue rigorosamente os princípios SOLID, código limpo e responsabilidade única. A arquitetura foi desenhada para ser aberta à expansão (adição de novos agentes e parsers) e fechada para alteração estrutural.

Todas as implementações devem ser acompanhadas de atualizações neste `README.md`. Os *commits* devem obrigatoriamente seguir o formato *Conventional Commits* (ex: `feat: adiciona script de health check`, `docs: melhora documentação arquitetural`). Certifique-se de que o código submetido seja funcional e esteja livre de erros de sintaxe.
