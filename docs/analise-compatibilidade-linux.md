# Análise de Compatibilidade Linux — Copilot Agents Local Setup

## Sumário Executivo

A análise conclui que **a stack completa é portável para Linux** com esforço moderado. Todas as ferramentas escolhidas possuem suporte nativo a Linux. O esforço concentra-se exclusivamente na **camada de scripts de automação** (PowerShell → Bash/Shell), pois a camada de ferramentas (binários, pacotes Python, configurações MCP) é intrinsecamente multiplataforma.

---

## 1. Compatibilidade das Ferramentas (Binários e Pacotes)

| Ferramenta | Windows | Linux | macOS | Observação |
|:---|:---:|:---:|:---:|:---|
| **codebase-memory-mcp** | ✅ amd64 | ✅ amd64 + arm64 | ✅ amd64 + arm64 | Binário estático único. Releases oficiais para todas as plataformas. |
| **Serena MCP** | ✅ via uv/pipx | ✅ via uv/pipx | ✅ via uv/pipx | Pacote Python puro (`serena-agent` no PyPI). Funciona em qualquer OS com Python 3.9+. |
| **Arize Phoenix** | ✅ via pip | ✅ via pip | ✅ via pip | Pacote Python puro (`arize-phoenix` no PyPI). Documentação oficial inclui guia para Ubuntu. |
| **Ollama** | ✅ user-level | ⚠️ requer workaround | ✅ nativo | No Linux, o instalador oficial usa `sudo`. Porém, é possível instalar em user-level manualmente (download do tarball + `OLLAMA_MODELS` em `$HOME`). |
| **uv** (Astral) | ✅ | ✅ | ✅ | Binário Rust multiplataforma. Instalação: `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| **mcp-proxy-logger.py** | ✅ | ✅ | ✅ | Python puro. Usa apenas `subprocess`, `threading`, `json`. Zero dependência de OS. |
| **MCP Inspector** | ✅ | ✅ | ✅ | Pacote npm (`@anthropic-ai/mcp-inspector`). Node.js multiplataforma. |
| **n8n** | ✅ | ✅ | ✅ | Pacote npm. Node.js multiplataforma. |

**Conclusão:** 100% das ferramentas possuem suporte Linux. O Ollama requer um workaround para instalação sem root, mas é viável.

---

## 2. Compatibilidade dos Scripts de Automação

### 2.1 Análise por Script

| Script | Complexidade de Portabilidade | Motivo |
|:---|:---:|:---|
| `setup-codebase-memory.ps1` | **Média** | Download do binário (mudar URL para `linux-amd64`), PATH via `~/.local/bin`, MCP config em `~/.config/github-copilot/` |
| `setup-serena.ps1` | **Baixa** | Remover workarounds Windows (TEMP curto, PE resources, UV_LINK_MODE). No Linux, `uv tool install serena-agent` funciona diretamente. |
| `setup-phoenix.ps1` | **Média** | Substituir `Start-Process`/`Stop-Process` por `nohup`/`kill`. PID file e log já são conceitos Unix nativos. |
| `index-workspace.ps1` | **Baixa** | Substituir `Get-ChildItem` por `find`, `Push-Location` por `cd`. Lógica é portável. |
| `health-check.ps1` | **Baixa** | Substituir `Get-Command` por `which`/`command -v`. Lógica trivial. |
| `inspect-mcp.ps1` | **Baixa** | Verificação de binários no PATH. Trivial em Bash. |
| `toggle-monitoring.ps1` | **Média** | Manipulação de JSON (`mcp.json`). Usar `jq` no Linux. |
| `generate-dashboard.ps1` | **Baixa** | Leitura de JSONL e geração de HTML. Python seria mais portável. |
| `optimize-environment.ps1` | **Baixa** | Configuração de variáveis de ambiente. Trivial em Bash. |
| `apply-ollama-tweaks.ps1` | **Baixa** | Variáveis de ambiente e `ollama` CLI. Portável. |
| `setup-mcp-inspector.ps1` | **Baixa** | `npx @anthropic-ai/mcp-inspector`. Idêntico em qualquer OS. |
| `setup-n8n.ps1` | **Baixa** | `npx n8n`. Idêntico em qualquer OS. |
| `setup-proxy-workaround.ps1` | **Média** | Certificados SSL corporativos. No Linux: `update-ca-certificates` ou variáveis `NODE_EXTRA_CA_CERTS`. |

### 2.2 Elementos Windows-Específicos a Substituir

| Elemento Windows | Equivalente Linux | Impacto |
|:---|:---|:---|
| `$env:USERPROFILE` | `$HOME` | Trivial |
| `$env:LOCALAPPDATA\Programs\` | `$HOME/.local/bin/` | Trivial |
| `[Environment]::SetEnvironmentVariable("PATH", ..., "User")` | Append em `~/.bashrc` ou `~/.profile` | Trivial |
| `Invoke-WebRequest` | `curl` ou `wget` | Trivial |
| `Expand-Archive` | `unzip` ou `tar -xzf` | Trivial |
| `Get-Command` | `command -v` ou `which` | Trivial |
| `Get-ChildItem -Recurse` | `find` | Trivial |
| `Start-Process -NoNewWindow` | `nohup ... &` | Trivial |
| `Stop-Process -Id $pid` | `kill $pid` | Trivial |
| `Get-NetTCPConnection` | `ss -tlnp` ou `lsof -i` | Trivial |
| `ConvertFrom-Json` / `ConvertTo-Json` | `jq` | Trivial |
| `Test-Path` | `[ -f ... ]` ou `[ -d ... ]` | Trivial |
| `Write-Host -ForegroundColor` | `echo -e "\033[...m"` (ANSI) | Trivial |
| `.exe` suffix | Sem sufixo | Trivial |
| `Join-Path` com `\` | Caminhos com `/` | Trivial |
| Workaround TEMP curto (MAX_PATH) | **Não necessário** (Linux não tem limite 260 chars) | Remoção |
| Workaround UV_LINK_MODE=copy | **Não necessário** (hardlinks funcionam nativamente) | Remoção |
| Workaround PE Resources/Trampoline | **Não necessário** (conceito exclusivo Windows) | Remoção |

---

## 3. Configuração do IntelliJ no Linux

A configuração do IntelliJ para MCP é **idêntica** em Windows e Linux:

| Aspecto | Windows | Linux |
|:---|:---|:---|
| Caminho do `mcp.json` | `%USERPROFILE%\.config\github-copilot\intellij\mcp.json` | `~/.config/github-copilot/intellij/mcp.json` |
| Settings path | `File → Settings → Tools → GitHub Copilot → MCP` | Idêntico |
| Plugin Copilot | JetBrains Marketplace | Idêntico |
| Formato do `mcp.json` | JSON com `"command": "codebase-memory-mcp.exe"` | JSON com `"command": "codebase-memory-mcp"` (sem `.exe`) |

A única diferença é a **ausência do sufixo `.exe`** no campo `command` do `mcp.json`.

---

## 4. Diferenças Operacionais Relevantes

### 4.1 Instalação sem Root (cenário corporativo Linux)

| Ferramenta | Instalação sem root no Linux |
|:---|:---|
| **codebase-memory-mcp** | ✅ Download do binário para `~/.local/bin/` |
| **Serena MCP** | ✅ `uv tool install serena-agent` (instala em `~/.local/`) |
| **Arize Phoenix** | ✅ `pip install --user arize-phoenix` ou venv |
| **uv** | ✅ `curl -LsSf https://astral.sh/uv/install.sh \| sh` (instala em `~/.local/bin/`) |
| **Ollama** | ⚠️ Workaround: baixar tarball manualmente, extrair em `~/.local/`, definir `OLLAMA_MODELS=$HOME/.ollama/models` |
| **Node.js** (para MCP Inspector, n8n) | ✅ `nvm install` ou download do tarball para `~/.local/` |

### 4.2 Gerenciamento de Processos Background

No Linux, o controle de processos é mais natural:

```bash
# Iniciar Phoenix em background
nohup python -m phoenix.server.main --port 6006 > ~/.phoenix/phoenix.log 2>&1 &
echo $! > ~/.phoenix/phoenix.pid

# Verificar status
kill -0 $(cat ~/.phoenix/phoenix.pid) 2>/dev/null && echo "Running" || echo "Stopped"

# Parar
kill $(cat ~/.phoenix/phoenix.pid)
```

### 4.3 Variáveis de Ambiente Persistentes

No Linux, variáveis de ambiente persistentes são configuradas em `~/.bashrc`, `~/.profile` ou `~/.config/environment.d/`:

```bash
# ~/.config/environment.d/copilot-agents.conf (systemd user env)
PHOENIX_PORT=6006
PHOENIX_TELEMETRY_ENABLED=false
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODELS=$HOME/.ollama/models
```

---

## 5. Estratégia de Portabilidade Recomendada

### Opção A: Scripts Bash Paralelos (Recomendada)

Criar versões `.sh` dos scripts principais, mantendo os `.ps1` para Windows:

```text
scripts/
├── setup-codebase-memory.ps1    # Windows
├── setup-codebase-memory.sh     # Linux/macOS
├── setup-serena.ps1             # Windows
├── setup-serena.sh              # Linux/macOS
├── setup-phoenix.ps1            # Windows
├── setup-phoenix.sh             # Linux/macOS
├── index-workspace.ps1          # Windows
├── index-workspace.sh           # Linux/macOS
└── health-check.ps1             # Windows
└── health-check.sh              # Linux/macOS
```

**Vantagens:** Simplicidade, idiomático para cada OS, sem dependência extra.
**Desvantagens:** Duplicação de lógica, manutenção em dois lugares.

### Opção B: PowerShell Cross-Platform

PowerShell 7+ (`pwsh`) funciona em Linux. Os scripts existentes precisariam de ajustes mínimos:

- Remover workarounds Windows-only
- Substituir `$env:LOCALAPPDATA` por `$HOME/.local`
- Remover `.exe` dos nomes de binários
- Substituir `Get-NetTCPConnection` por `ss` via `Invoke-Expression`

**Vantagens:** Reutiliza 80% do código existente, manutenção única.
**Desvantagens:** Requer instalação do `pwsh` no Linux (dependência extra), menos idiomático.

### Opção C: Makefile Unificado

Um `Makefile` com targets que detectam o OS e chamam o script correto:

```makefile
OS := $(shell uname -s)

setup-codebase-memory:
ifeq ($(OS),Linux)
	./scripts/setup-codebase-memory.sh
else
	powershell -ExecutionPolicy Bypass -File ./scripts/setup-codebase-memory.ps1
endif
```

**Vantagens:** Interface unificada (`make setup`), familiar para desenvolvedores Linux.
**Desvantagens:** Mais uma camada de abstração.

---

## 6. Estimativa de Esforço

| Componente | Esforço | Horas Estimadas |
|:---|:---:|:---:|
| `setup-codebase-memory.sh` | Médio | 2-3h |
| `setup-serena.sh` | Baixo | 1-2h (mais simples sem workarounds) |
| `setup-phoenix.sh` | Médio | 2-3h |
| `index-workspace.sh` | Baixo | 1-2h |
| `health-check.sh` | Baixo | 1h |
| `toggle-monitoring.sh` | Baixo | 1h |
| Testes e validação | Médio | 3-4h |
| Documentação (README Linux) | Baixo | 2h |
| **Total** | | **~14-18h** |

---

## 7. Conclusão

A mesma stack pode ser mantida no Linux **sem nenhuma substituição de ferramenta**. O codebase-memory-mcp, Serena, Phoenix e Ollama possuem suporte nativo. Os workarounds Windows-específicos (TEMP curto, PE resources, UV_LINK_MODE) simplesmente **deixam de ser necessários** no Linux, tornando os scripts Linux mais simples que os equivalentes Windows.

A recomendação é seguir a **Opção A** (scripts Bash paralelos) para os 5-6 scripts principais, pois:
1. É a abordagem mais idiomática para cada plataforma
2. Elimina a dependência de `pwsh` no Linux
3. Os scripts Linux serão significativamente mais simples (sem workarounds)
4. A lógica de negócio (qual ferramenta instalar, onde configurar) é documentada no README e nos templates de `mcp.json`, que são idênticos em ambas as plataformas
