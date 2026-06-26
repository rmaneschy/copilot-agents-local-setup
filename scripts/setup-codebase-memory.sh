#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup-codebase-memory.sh — Instala e configura o codebase-memory-mcp (Linux)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Instala o codebase-memory-mcp, um motor de code intelligence de alta
# performance que indexa código-fonte em um knowledge graph persistente,
# expondo 14 ferramentas MCP para busca semântica, call graph, análise de
# impacto e arquitetura.
#
# Características:
#   - Binário estático único (C puro) — zero dependências
#   - Modelo de embedding (nomic-embed-code, 768d) compilado no binário
#   - 158 linguagens via tree-sitter vendored
#   - 100% offline desde o primeiro uso
#   - Auto-sync via git-based change detection
#
# Uso:
#   ./scripts/setup-codebase-memory.sh [opções]
#
# Opções:
#   --workspace PATH     Caminho do workspace (padrão: ~/workspace)
#   --scope project|workspace  Escopo de indexação (padrão: project)
#   --variant standard|ui      Variante do binário (padrão: standard)
#   --install-dir PATH   Diretório de instalação (padrão: ~/.local/bin)
#   --skip-index         Pula indexação inicial
#   --auto-index         Habilita indexação automática
#   --uninstall          Remove o codebase-memory-mcp
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
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# Parâmetros (defaults)
# ─────────────────────────────────────────────────────────────────────────────
WORKSPACE_PATH="${HOME}/workspace"
SCOPE="project"
VARIANT="standard"
INSTALL_DIR="${HOME}/.local/bin"
SKIP_INDEX=false
AUTO_INDEX=false
UNINSTALL=false

# ─────────────────────────────────────────────────────────────────────────────
# Parse de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)    WORKSPACE_PATH="$2"; shift 2 ;;
        --scope)        SCOPE="$2"; shift 2 ;;
        --variant)      VARIANT="$2"; shift 2 ;;
        --install-dir)  INSTALL_DIR="$2"; shift 2 ;;
        --skip-index|--SkipIndex)   SKIP_INDEX=true; shift ;;
        --auto-index)   AUTO_INDEX=true; shift ;;
        --uninstall|-Uninstall)    UNINSTALL=true; shift ;;
        *)              echo -e "${RED}Opção desconhecida: $1${NC}"; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────────────────────
REPO="DeusData/codebase-memory-mcp"
BIN_NAME="codebase-memory-mcp"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"

# Detectar arquitetura
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    arm64)   ARCH_SUFFIX="arm64" ;;
    *)       echo -e "${RED}Arquitetura não suportada: ${ARCH}${NC}"; exit 1 ;;
esac

# Detectar OS
UNAME_S=$(uname -s)
case "$UNAME_S" in
    Linux)  OS_SUFFIX="linux" ;;
    Darwin) OS_SUFFIX="darwin" ;;
    *)      echo -e "${RED}OS não suportado: ${UNAME_S}${NC}"; exit 1 ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  codebase-memory-mcp — Setup Plug-and-Play (Linux)          ║${NC}"
echo -e "${CYAN}║  Code Intelligence via Knowledge Graph + MCP                ║${NC}"
echo -e "${CYAN}║  Zero dependências · 158 linguagens · 100% offline          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Modo: Uninstall
# ─────────────────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    echo -e "${YELLOW}  [MODO DESINSTALAÇÃO] Removendo codebase-memory-mcp...${NC}"
    echo ""

    # Executar uninstall nativo
    if [ -f "$BIN_PATH" ]; then
        "$BIN_PATH" uninstall -y 2>/dev/null || true
        echo -e "${GRAY}    OK: Configurações de agentes removidas.${NC}"
    fi

    # Remover binário
    if [ -f "$BIN_PATH" ]; then
        rm -f "$BIN_PATH"
        echo -e "${GRAY}    REMOVIDO: ${BIN_PATH}${NC}"
    else
        echo -e "${GRAY}    NÃO ENCONTRADO: ${BIN_PATH}${NC}"
    fi

    # Remover entrada do mcp.json
    MCP_JSON_PATH="${HOME}/.config/github-copilot/intellij/mcp.json"
    if [ -f "$MCP_JSON_PATH" ] && command -v jq &>/dev/null; then
        jq 'del(.servers["code-search"]) | del(.servers["codebase-memory"])' \
            "$MCP_JSON_PATH" > "${MCP_JSON_PATH}.tmp" && \
            mv "${MCP_JSON_PATH}.tmp" "$MCP_JSON_PATH"
        echo -e "${GRAY}    REMOVIDO do mcp.json: entrada code-search${NC}"
    fi

    echo ""
    echo -e "${GREEN}  OK: codebase-memory-mcp removido com sucesso.${NC}"
    echo ""
    echo -e "${GRAY}  Nota: Índices locais (.codebase-memory/) nos projetos NÃO foram removidos.${NC}"
    echo -e "${GRAY}  Para remover: find ~/workspace -name '.codebase-memory' -type d -exec rm -rf {} +${NC}"
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 1: Verificar instalação existente e comparar versão
# ─────────────────────────────────────────────────────────────────────────────
echo -e "  ${NC}[1/4] Verificando instalação existente...${NC}"

SKIP_DOWNLOAD=false
if command -v "$BIN_NAME" &>/dev/null; then
    CURRENT_VERSION=$("$BIN_NAME" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
    echo -e "${CYAN}    Versao local: ${CURRENT_VERSION}${NC}"

    # Consultar versao mais recente via GitHub API
    LATEST_VERSION=""
    if command -v curl &>/dev/null; then
        LATEST_VERSION=$(curl -fsSL --connect-timeout 10 \
            "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
            grep -oP '"tag_name":\s*"v?\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    fi

    if [ -n "$LATEST_VERSION" ]; then
        echo -e "${CYAN}    Versao remota: ${LATEST_VERSION}${NC}"
        if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
            echo -e "${GREEN}    OK: Ja esta na versao mais recente. Download desnecessario.${NC}"
            SKIP_DOWNLOAD=true
        else
            echo -e "${YELLOW}    Atualizacao disponivel: ${CURRENT_VERSION} -> ${LATEST_VERSION}${NC}"
        fi
    else
        echo -e "${YELLOW}    AVISO: Nao foi possivel consultar versao remota (sem internet?).${NC}"
        echo -e "${YELLOW}    Mantendo versao atual instalada.${NC}"
        SKIP_DOWNLOAD=true
    fi
else
    echo -e "${GRAY}    Nenhuma instalacao anterior detectada. Instalacao limpa.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 2: Download e instalação do binário (skip se já atualizado)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_DOWNLOAD" = false ]; then
echo ""
echo -e "  ${NC}[2/4] Baixando codebase-memory-mcp (${VARIANT}, ${OS_SUFFIX}-${ARCH_SUFFIX})...${NC}"

# Determinar arquivo de download
if [ "$VARIANT" = "ui" ]; then
    ARCHIVE="codebase-memory-mcp-ui-${OS_SUFFIX}-${ARCH_SUFFIX}.tar.gz"
else
    ARCHIVE="codebase-memory-mcp-${OS_SUFFIX}-${ARCH_SUFFIX}.tar.gz"
fi
DOWNLOAD_URL="${BASE_URL}/${ARCHIVE}"

# Criar diretório temporário
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

echo -e "${GRAY}    URL: ${DOWNLOAD_URL}${NC}"
echo "    Baixando (~15MB)..."

# Download
if command -v curl &>/dev/null; then
    curl -fsSL -o "${TMP_DIR}/${ARCHIVE}" "$DOWNLOAD_URL"
elif command -v wget &>/dev/null; then
    wget -q -O "${TMP_DIR}/${ARCHIVE}" "$DOWNLOAD_URL"
else
    echo -e "${RED}    ERRO: Nem curl nem wget encontrados.${NC}"
    exit 1
fi

# Verificação de checksum
echo "    Verificando integridade (SHA-256)..."
CHECKSUM_URL="${BASE_URL}/checksums.txt"
if curl -fsSL -o "${TMP_DIR}/checksums.txt" "$CHECKSUM_URL" 2>/dev/null; then
    EXPECTED=$(grep "$ARCHIVE" "${TMP_DIR}/checksums.txt" | awk '{print $1}')
    if [ -n "$EXPECTED" ]; then
        ACTUAL=$(sha256sum "${TMP_DIR}/${ARCHIVE}" | awk '{print $1}')
        if [ "$EXPECTED" != "$ACTUAL" ]; then
            echo -e "${RED}    ERRO: CHECKSUM MISMATCH!${NC}"
            echo -e "${RED}    Esperado: ${EXPECTED}${NC}"
            echo -e "${RED}    Obtido:   ${ACTUAL}${NC}"
            exit 1
        fi
        echo -e "${GREEN}    OK: Checksum verificado.${NC}"
    else
        echo -e "${YELLOW}    AVISO: Arquivo não encontrado no checksums.txt (verificação pulada).${NC}"
    fi
else
    echo -e "${YELLOW}    AVISO: Não foi possível verificar checksum (non-fatal).${NC}"
fi

# Extrair
echo "    Extraindo..."
tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "${TMP_DIR}"

# Localizar binário extraído
DL_BIN=$(find "${TMP_DIR}" -name "${BIN_NAME}" -type f | head -1)
if [ -z "$DL_BIN" ]; then
    # Tentar variante UI
    DL_BIN=$(find "${TMP_DIR}" -name "codebase-memory-mcp-ui" -type f | head -1)
    if [ -z "$DL_BIN" ]; then
        echo -e "${RED}    ERRO: Binário não encontrado após extração.${NC}"
        exit 1
    fi
fi

# Instalar
mkdir -p "$INSTALL_DIR"
cp "$DL_BIN" "$BIN_PATH"
chmod +x "$BIN_PATH"

# Verificar instalação
INSTALLED_VERSION=$("$BIN_PATH" --version 2>&1 || echo "instalado")
echo -e "${GREEN}    OK: ${INSTALLED_VERSION} instalado em ${INSTALL_DIR}${NC}"

fi # Fim do if SKIP_DOWNLOAD

# Garantir que ~/.local/bin está no PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    # Adicionar ao .bashrc se não estiver
    SHELL_RC="${HOME}/.bashrc"
    if [ -f "${HOME}/.zshrc" ] && [ "$SHELL" = "/bin/zsh" ]; then
        SHELL_RC="${HOME}/.zshrc"
    fi
    if ! grep -q "${INSTALL_DIR}" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# codebase-memory-mcp" >> "$SHELL_RC"
        echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$SHELL_RC"
        echo -e "${GRAY}    Adicionado ao PATH em ${SHELL_RC}${NC}"
    fi
    export PATH="${INSTALL_DIR}:$PATH"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 3: Configurar MCP para GitHub Copilot no IntelliJ
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${NC}[3/4] Configurando integração MCP para IntelliJ Copilot...${NC}"

MCP_CONFIG_DIR="${HOME}/.config/github-copilot/intellij"
MCP_JSON_PATH="${MCP_CONFIG_DIR}/mcp.json"

mkdir -p "$MCP_CONFIG_DIR"

# Criar ou atualizar mcp.json
if [ -f "$MCP_JSON_PATH" ] && command -v jq &>/dev/null; then
    # Atualizar configuração existente com jq
    jq --arg bin "$BIN_PATH" \
       '.servers["code-search"] = {"type": "stdio", "command": $bin, "args": []}' \
       "$MCP_JSON_PATH" > "${MCP_JSON_PATH}.tmp" && \
       mv "${MCP_JSON_PATH}.tmp" "$MCP_JSON_PATH"
    echo -e "${GREEN}    OK: mcp.json atualizado com servidor 'code-search'${NC}"
else
    # Criar novo mcp.json
    cat > "$MCP_JSON_PATH" << EOF
{
  "servers": {
    "code-search": {
      "type": "stdio",
      "command": "${BIN_PATH}",
      "args": []
    }
  }
}
EOF
    echo -e "${GREEN}    OK: mcp.json criado com servidor 'code-search'${NC}"
fi
echo -e "${GRAY}    Arquivo: ${MCP_JSON_PATH}${NC}"

# Habilitar auto-index se solicitado
if [ "$AUTO_INDEX" = true ]; then
    "$BIN_PATH" config set auto_index true 2>/dev/null || true
    echo -e "${GREEN}    OK: Auto-index habilitado.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 4: Indexação inicial do workspace (opcional)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${NC}[4/4] Indexação do workspace...${NC}"

if [ "$SKIP_INDEX" = true ]; then
    echo -e "${YELLOW}    SKIP: Indexação pulada (flag --skip-index).${NC}"
    echo -e "${GRAY}    O índice será criado automaticamente na primeira busca.${NC}"
elif [ ! -d "$WORKSPACE_PATH" ]; then
    echo -e "${YELLOW}    SKIP: Diretório não encontrado: ${WORKSPACE_PATH}${NC}"
    echo -e "${GRAY}    O índice será criado quando você abrir um projeto.${NC}"
else
    echo -e "${CYAN}    Modo: ${SCOPE}${NC}"
    echo -e "${CYAN}    Indexando: ${WORKSPACE_PATH}${NC}"
    echo "    Iniciando indexação..."
    echo ""

    if (cd "$WORKSPACE_PATH" && "$BIN_PATH" index 2>&1); then
        echo -e "${GREEN}    OK: Workspace indexado com sucesso.${NC}"
    else
        echo -e "${YELLOW}    AVISO: Falha na indexação inicial (non-fatal).${NC}"
        echo -e "${GRAY}    O índice será criado na primeira busca via Copilot.${NC}"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  INSTALAÇÃO CONCLUÍDA COM SUCESSO                           ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Componente:  codebase-memory-mcp (Knowledge Graph + MCP)   ║${NC}"
echo -e "${GREEN}║  Variante:    ${VARIANT}                                    ║${NC}"
echo -e "${GREEN}║  Binário:     ${BIN_PATH}                                   ║${NC}"
echo -e "${GREEN}║  MCP Config:  ${MCP_JSON_PATH}                              ║${NC}"
echo -e "${GREEN}║  Plataforma:  ${OS_SUFFIX}-${ARCH_SUFFIX}                   ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Próximos passos:                                           ║${NC}"
echo -e "${GREEN}║  1. Reinicie o IntelliJ IDEA                                ║${NC}"
echo -e "${GREEN}║  2. Verifique 'code-search' em Copilot Chat → Tools         ║${NC}"
echo -e "${GREEN}║  3. Diga ao agente: 'Index this project'                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
