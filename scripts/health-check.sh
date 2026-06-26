#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# health-check.sh — Verificação de saúde dos componentes MCP (Linux)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Verifica a disponibilidade e funcionamento de todos os componentes do
# ambiente de agentes autônomos GitHub Copilot.
#
# Componentes verificados:
#   - codebase-memory-mcp (code-search)
#   - Serena MCP (code-navigation)
#   - Arize Phoenix (observabilidade)
#   - Ollama (LLM local, opcional)
#   - mcp.json (configuração)
#
# Uso:
#   ./scripts/health-check.sh [opções]
#
# Opções:
#   --verbose    Exibe detalhes adicionais
#   --json       Saída em formato JSON
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
VERBOSE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)  VERBOSE=true; shift ;;
        --json)     JSON_OUTPUT=true; shift ;;
        *)          echo -e "${RED}Opção desconhecida: $1${NC}"; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Contadores
# ─────────────────────────────────────────────────────────────────────────────
TOTAL=0
PASS=0
WARN=0
FAIL=0

# ─────────────────────────────────────────────────────────────────────────────
# Funções de verificação
# ─────────────────────────────────────────────────────────────────────────────
check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    if [ "$VERBOSE" = true ] && [ -n "${2:-}" ]; then
        echo -e "    ${GRAY}$2${NC}"
    fi
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    TOTAL=$((TOTAL + 1))
    WARN=$((WARN + 1))
    if [ -n "${2:-}" ]; then
        echo -e "    ${GRAY}$2${NC}"
    fi
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    if [ -n "${2:-}" ]; then
        echo -e "    ${GRAY}$2${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Health Check — Ambiente de Agentes MCP                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# 1. codebase-memory-mcp (code-search)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "  ${CYAN}[code-search] codebase-memory-mcp${NC}"
fi

if command -v codebase-memory-mcp &>/dev/null; then
    VERSION=$(codebase-memory-mcp --version 2>&1 || echo "desconhecida")
    check_pass "Binário encontrado" "Versão: ${VERSION}"
else
    check_fail "Binário não encontrado" "Execute: make install-code-search"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. Serena MCP (code-navigation)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "  ${CYAN}[code-navigation] Serena MCP${NC}"
fi

if command -v serena &>/dev/null; then
    VERSION=$(serena --version 2>&1 || echo "desconhecida")
    check_pass "Binário encontrado" "Versão: ${VERSION}"
else
    check_fail "Binário não encontrado" "Execute: make install-code-navigation"
fi

# Verificar configuração
SERENA_CONFIG="${HOME}/.serena/serena_config.yml"
if [ -f "$SERENA_CONFIG" ]; then
    check_pass "Configuração presente" "${SERENA_CONFIG}"
else
    check_warn "Configuração ausente" "Será criada na primeira execução"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. Arize Phoenix (observabilidade)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "  ${CYAN}[observability] Arize Phoenix${NC}"
fi

PHOENIX_VENV="${HOME}/.phoenix/venv"
if [ -f "${PHOENIX_VENV}/bin/activate" ]; then
    # Verificar se phoenix está instalado no venv
    PHOENIX_VERSION=$(source "${PHOENIX_VENV}/bin/activate" && python3 -c "import phoenix; print(phoenix.__version__)" 2>/dev/null || echo "")
    if [ -n "$PHOENIX_VERSION" ]; then
        check_pass "Instalado" "Versão: ${PHOENIX_VERSION}"
    else
        check_fail "Venv existe mas Phoenix não importável" "Execute: make install-observability"
    fi
else
    check_warn "Não instalado (opcional)" "Execute: make install-observability"
fi

# Verificar se está rodando
PID_FILE="${HOME}/.phoenix/phoenix.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    check_pass "Servidor rodando" "PID $(cat "$PID_FILE") — http://localhost:6006"
else
    check_warn "Servidor parado" "Inicie com: make start-phoenix"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 4. Ollama (LLM local, opcional)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "  ${CYAN}[llm-local] Ollama (opcional)${NC}"
fi

if command -v ollama &>/dev/null; then
    OLLAMA_VERSION=$(ollama --version 2>&1 || echo "desconhecida")
    check_pass "Binário encontrado" "Versão: ${OLLAMA_VERSION}"

    # Verificar se está rodando
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        check_pass "Servidor rodando" "http://localhost:11434"

        # Verificar modelos disponíveis
        MODELS=$(curl -s http://localhost:11434/api/tags | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = [m['name'] for m in data.get('models', [])]
print(', '.join(models[:5]) if models else 'nenhum')
" 2>/dev/null || echo "erro ao listar")
        if [ "$VERBOSE" = true ]; then
            echo -e "    ${GRAY}Modelos: ${MODELS}${NC}"
        fi
    else
        check_warn "Servidor parado" "Inicie com: ollama serve"
    fi
else
    check_warn "Não instalado (opcional)" "Necessário apenas para modo offline"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 5. Configuração MCP (mcp.json)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "  ${CYAN}[config] mcp.json${NC}"
fi

MCP_JSON="${HOME}/.config/github-copilot/intellij/mcp.json"
if [ -f "$MCP_JSON" ]; then
    check_pass "Arquivo encontrado" "${MCP_JSON}"

    # Verificar servidores configurados
    if command -v jq &>/dev/null; then
        SERVERS=$(jq -r '.servers | keys[]' "$MCP_JSON" 2>/dev/null || echo "")
        if [ -n "$SERVERS" ]; then
            for server in $SERVERS; do
                check_pass "Servidor configurado: ${server}"
            done
        else
            check_warn "Nenhum servidor configurado" "Execute: make install"
        fi
    else
        check_warn "jq não disponível" "Instale jq para validação detalhada"
    fi
else
    check_fail "Arquivo não encontrado" "Execute: make install"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 6. Dependências do sistema
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "  ${CYAN}[system] Dependências${NC}"
fi

# Python
if command -v python3 &>/dev/null; then
    PY_VERSION=$(python3 --version 2>&1)
    check_pass "Python: ${PY_VERSION}"
else
    check_fail "Python 3 não encontrado"
fi

# jq
if command -v jq &>/dev/null; then
    check_pass "jq: $(jq --version 2>&1)"
else
    check_warn "jq não encontrado" "Recomendado para manipulação de mcp.json"
fi

# curl
if command -v curl &>/dev/null; then
    check_pass "curl: disponível"
else
    check_fail "curl não encontrado"
fi

# git
if command -v git &>/dev/null; then
    GIT_VERSION=$(git --version 2>&1)
    check_pass "git: ${GIT_VERSION}"
else
    check_fail "git não encontrado"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Resumo
# ─────────────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"total\": ${TOTAL}, \"pass\": ${PASS}, \"warn\": ${WARN}, \"fail\": ${FAIL}}"
else
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  RESUMO"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Total:    ${TOTAL} verificações"
    echo -e "  Sucesso:  ${GREEN}${PASS}${NC}"
    echo -e "  Avisos:   ${YELLOW}${WARN}${NC}"
    echo -e "  Falhas:   ${RED}${FAIL}${NC}"
    echo ""

    if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
        echo -e "  ${GREEN}Ambiente 100% operacional. Todos os componentes funcionando.${NC}"
    elif [ "$FAIL" -eq 0 ]; then
        echo -e "  ${YELLOW}Ambiente operacional com avisos. Componentes opcionais ausentes.${NC}"
    else
        echo -e "  ${RED}Ambiente com falhas. Execute 'make install' para corrigir.${NC}"
    fi
    echo ""
fi

# Exit code baseado em falhas
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
