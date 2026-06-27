#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup-serena.sh — Instala e configura o Serena MCP (Linux)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Instala o Serena MCP via uv (ou pipx como fallback), que fornece ferramentas
# semânticas de navegação de código (via LSP) ao GitHub Copilot Agent Mode.
#
# O Serena complementa o code-search com capacidades determinísticas:
#   - find_symbol, get_symbol_overview
#   - find_references, get_implementations
#   - apply_edit, rename_symbol
#
# Uso:
#   ./scripts/setup-serena.sh [opções]
#
# Opções:
#   --workspace PATH     Caminho do workspace (padrão: ~/workspace)
#   --force-reinstall    Força reinstalação completa
#   --use-pipx           Usa pipx em vez de uv
#
# Autor: Rodrigo Maneschy
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Cores
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Parâmetros
# ─────────────────────────────────────────────────────────────────────────────
WORKSPACE_PATH="${HOME}/workspace"
FORCE_REINSTALL=false
USE_PIPX=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)        WORKSPACE_PATH="$2"; shift 2 ;;
        --force-reinstall)  FORCE_REINSTALL=true; shift ;;
        --use-pipx)         USE_PIPX=true; shift ;;
        *)                  echo -e "${RED}Opção desconhecida: $1${NC}"; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Serena MCP — Setup para GitHub Copilot (Linux)             ║${NC}"
echo -e "${CYAN}║  Navegação Semântica de Código (LSP)                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 1: Verificar/Instalar uv
# ─────────────────────────────────────────────────────────────────────────────
echo -e "  [1/4] Verificando gerenciador de pacotes Python..."

install_uv() {
    echo -e "${GRAY}    Instalando uv...${NC}"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:$PATH"
}

if [ "$USE_PIPX" = false ]; then
    if ! command -v uv &>/dev/null; then
        install_uv
    fi
    UV_VERSION=$(uv --version 2>&1)
    echo -e "${GREEN}    OK: uv ${UV_VERSION}${NC}"
    INSTALLER="uv"
else
    if ! command -v pipx &>/dev/null; then
        echo -e "${GRAY}    Instalando pipx...${NC}"
        python3 -m pip install --user pipx
        python3 -m pipx ensurepath
        export PATH="${HOME}/.local/bin:$PATH"
    fi
    PIPX_VERSION=$(pipx --version 2>&1)
    echo -e "${GREEN}    OK: pipx ${PIPX_VERSION}${NC}"
    INSTALLER="pipx"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 2: Instalar Serena
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  [2/4] Instalando Serena MCP..."

if [ "$FORCE_REINSTALL" = true ]; then
    echo -e "${YELLOW}    Removendo instalação anterior...${NC}"
    if [ "$INSTALLER" = "uv" ]; then
        uv tool uninstall serena-agent 2>/dev/null || true
    else
        pipx uninstall serena-agent 2>/dev/null || true
    fi
fi

if [ "$INSTALLER" = "uv" ]; then
    uv tool install serena-agent
else
    pipx install serena-agent
fi

# Verificar instalação
if command -v serena &>/dev/null; then
    SERENA_VERSION=$(serena --version 2>&1 || echo "instalado")
    echo -e "${GREEN}    OK: Serena ${SERENA_VERSION}${NC}"
else
    echo -e "${RED}    ERRO: Serena não encontrado no PATH após instalação.${NC}"
    echo -e "${GRAY}    Verifique se ~/.local/bin está no PATH.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 3: Configurar serena_config.yml
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  [3/4] Configurando Serena..."

SERENA_CONFIG_DIR="${HOME}/.serena"
SERENA_CONFIG_FILE="${SERENA_CONFIG_DIR}/serena_config.yml"

mkdir -p "$SERENA_CONFIG_DIR"

if [ ! -f "$SERENA_CONFIG_FILE" ] || [ "$FORCE_REINSTALL" = true ]; then
    if [ -f "$SERENA_CONFIG_FILE" ]; then
        cp "$SERENA_CONFIG_FILE" "${SERENA_CONFIG_FILE}.bak"
        echo -e "${GRAY}    Backup: ${SERENA_CONFIG_FILE}.bak${NC}"
    fi
    cat > "$SERENA_CONFIG_FILE" << EOF
# ═══════════════════════════════════════════════════════════════════════════════
# SERENA GLOBAL CONFIG
# Otimizado para IntelliJ + GitHub Copilot Agent Mode
# Gerado automaticamente por setup-serena.sh
# Documentação: https://oraios.github.io/serena/02-usage/050_configuration.html
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Backend ───────────────────────────────────────────────────────────────
language_backend: JetBrains
line_ending: native

# ─── Dashboard Web ──────────────────────────────────────────────────────────
web_dashboard: True
web_dashboard_open_on_launch: False
web_dashboard_interface: browser
web_dashboard_listen_address: 127.0.0.1

# ─── JetBrains Integration ─────────────────────────────────────────────────
jetbrains_plugin_server_address: 127.0.0.1

# ─── Logging ───────────────────────────────────────────────────────────────
log_level: 20
gui_log_window: False
trace_lsp_communication: False

# ─── Performance ───────────────────────────────────────────────────────────
tool_timeout: 120
default_max_tool_answer_chars: 150000
token_count_estimator: CHAR_COUNT

# ─── Modes ────────────────────────────────────────────────────────────────
base_modes:
  - interactive
  - editing
default_modes:
  - planning

# ─── Paths Ignorados Globalmente ───────────────────────────────────────────
ignored_paths:
  - "**/node_modules/**"
  - "**/target/**"
  - "**/build/**"
  - "**/.gradle/**"
  - "**/dist/**"
  - "**/.idea/**"
  - "**/.git/**"
  - "**/vendor/**"
  - "**/__pycache__/**"
  - "**/bin/**"
  - "**/obj/**"

# ─── Tools ────────────────────────────────────────────────────────────────
excluded_tools: []
included_optional_tools: []

# ─── Memories ─────────────────────────────────────────────────────────────
read_only_memory_patterns:
  - "global/.*"
ignored_memory_patterns:
  - "_archive/.*"
  - "_episodes/.*"

# ─── Projects (obrigatório desde Serena 1.1+) ────────────────────────────────
# Lista de caminhos de projetos registrados. O Serena exige esta chave.
# Adicione os caminhos dos projetos que deseja usar com o Serena.
# O agente pode registrar projetos automaticamente via 'activate_project'.
projects:
  - ${WORKSPACE_PATH}
EOF
    echo -e "${GREEN}    OK: Configuração criada em ${SERENA_CONFIG_FILE}${NC}"
else
    # Verificar se o config existente tem a chave 'projects'
    if ! grep -q "^projects:" "$SERENA_CONFIG_FILE" 2>/dev/null; then
        echo -e "${YELLOW}    AVISO: Adicionando chave 'projects' ao config existente...${NC}"
        cat >> "$SERENA_CONFIG_FILE" << EOF

# ─── Projects (obrigatório desde Serena 1.1+) ────────────────────────────────
projects:
  - ${WORKSPACE_PATH}
EOF
        echo -e "${GREEN}    OK: Chave 'projects' adicionada${NC}"
    else
        echo -e "${CYAN}    Configuração existente preservada: ${SERENA_CONFIG_FILE}${NC}"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 4: Configurar MCP para IntelliJ
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  [4/4] Configurando integração MCP para IntelliJ Copilot..."

MCP_CONFIG_DIR="${HOME}/.config/github-copilot/intellij"
MCP_JSON_PATH="${MCP_CONFIG_DIR}/mcp.json"

mkdir -p "$MCP_CONFIG_DIR"

SERENA_BIN=$(command -v serena)

if [ -f "$MCP_JSON_PATH" ] && command -v jq &>/dev/null; then
    # Atualizar configuração existente
    jq --arg bin "$SERENA_BIN" \
       '.servers["code-navigation"] = {"type": "stdio", "command": $bin, "args": ["start-mcp-server"]}' \
       "$MCP_JSON_PATH" > "${MCP_JSON_PATH}.tmp" && \
       mv "${MCP_JSON_PATH}.tmp" "$MCP_JSON_PATH"
    echo -e "${GREEN}    OK: mcp.json atualizado com servidor 'code-navigation'${NC}"
else
    # Criar ou sobrescrever mcp.json
    if [ -f "$MCP_JSON_PATH" ]; then
        echo -e "${YELLOW}    AVISO: jq não encontrado. Criando mcp.json novo (backup salvo).${NC}"
        cp "$MCP_JSON_PATH" "${MCP_JSON_PATH}.bak"
    fi
    cat > "$MCP_JSON_PATH" << EOF
{
  "servers": {
    "code-navigation": {
      "type": "stdio",
      "command": "${SERENA_BIN}",
      "args": ["start-mcp-server"]
    }
  }
}
EOF
    echo -e "${GREEN}    OK: mcp.json criado com servidor 'code-navigation'${NC}"
fi
echo -e "${GRAY}    Arquivo: ${MCP_JSON_PATH}${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  INSTALAÇÃO CONCLUÍDA COM SUCESSO                           ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Componente:  Serena MCP (Navegação LSP)                    ║${NC}"
echo -e "${GREEN}║  Instalador:  ${INSTALLER}                                  ║${NC}"
echo -e "${GREEN}║  Config:      ${SERENA_CONFIG_FILE}                         ║${NC}"
echo -e "${GREEN}║  MCP:         ${MCP_JSON_PATH}                              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Tools MCP disponíveis:                                     ║${NC}"
echo -e "${GREEN}║  · find_symbol         · get_symbol_overview                ║${NC}"
echo -e "${GREEN}║  · find_references     · get_implementations                ║${NC}"
echo -e "${GREEN}║  · apply_edit          · rename_symbol                      ║${NC}"
echo -e "${GREEN}║  · get_diagnostics     · get_workspace_symbols              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Próximos passos:                                           ║${NC}"
echo -e "${GREEN}║  1. Reinicie o IntelliJ IDEA                                ║${NC}"
echo -e "${GREEN}║  2. Verifique 'code-navigation' em Copilot Chat → Tools     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
