#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup-phoenix.sh — Instala e gerencia o Arize Phoenix (Linux)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Instala o Arize Phoenix para observabilidade de agentes MCP. Permite
# visualizar traces de decisões, tool calls, latência e erros em tempo real.
#
# Características:
#   - Instalação via pip (sem Docker, sem admin)
#   - Backend SQLite (zero configuração)
#   - UI em http://localhost:6006
#   - Integração via OpenTelemetry (OTLP/gRPC)
#   - Modo air-gapped para ambientes corporativos
#
# Uso:
#   ./scripts/setup-phoenix.sh [opções]
#
# Opções:
#   --start              Inicia o servidor Phoenix
#   --stop               Para o servidor Phoenix
#   --status             Verifica status do servidor
#   --air-gapped         Configura modo offline (sem Google Fonts)
#   --port PORT          Porta do servidor (padrão: 6006)
#   --force-reinstall    Força reinstalação completa
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
ACTION="install"
AIR_GAPPED=false
PORT=6006
FORCE_REINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --start|-Start)         ACTION="start"; shift ;;
        --stop|-Stop)           ACTION="stop"; shift ;;
        --status)               ACTION="status"; shift ;;
        --air-gapped|-AirGapped) AIR_GAPPED=true; shift ;;
        --port)                 PORT="$2"; shift 2 ;;
        --force-reinstall)      FORCE_REINSTALL=true; shift ;;
        *)                      echo -e "${RED}Opção desconhecida: $1${NC}"; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────────────────────
PHOENIX_DIR="${HOME}/.phoenix"
PID_FILE="${PHOENIX_DIR}/phoenix.pid"
LOG_FILE="${PHOENIX_DIR}/phoenix.log"
VENV_DIR="${PHOENIX_DIR}/venv"

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Arize Phoenix — Agent Observability (Linux)                ║${NC}"
echo -e "${CYAN}║  Tracing de Decisões dos Agentes MCP                        ║${NC}"
echo -e "${CYAN}║  UI: http://localhost:${PORT}                               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Funções auxiliares
# ─────────────────────────────────────────────────────────────────────────────
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

activate_venv() {
    if [ -f "${VENV_DIR}/bin/activate" ]; then
        source "${VENV_DIR}/bin/activate"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Ação: Status
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "status" ]; then
    if is_running; then
        local_pid=$(cat "$PID_FILE")
        echo -e "${GREEN}  ✓ Phoenix rodando (PID ${local_pid})${NC}"
        echo -e "${GRAY}    UI: http://localhost:${PORT}${NC}"
        echo -e "${GRAY}    OTLP: http://localhost:4317 (gRPC)${NC}"
        echo -e "${GRAY}    Log: ${LOG_FILE}${NC}"
    else
        echo -e "${YELLOW}  ✗ Phoenix parado${NC}"
    fi
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Ação: Stop
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "stop" ]; then
    if is_running; then
        local_pid=$(cat "$PID_FILE")
        kill "$local_pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo -e "${GREEN}  ✓ Phoenix parado (PID ${local_pid})${NC}"
    else
        echo -e "${YELLOW}  Phoenix já estava parado.${NC}"
    fi
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Ação: Start (pula instalação se já instalado)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "start" ]; then
    if is_running; then
        local_pid=$(cat "$PID_FILE")
        echo -e "${YELLOW}  Phoenix já está rodando (PID ${local_pid}).${NC}"
        echo -e "${GRAY}    UI: http://localhost:${PORT}${NC}"
        echo ""
        exit 0
    fi

    if [ ! -f "${VENV_DIR}/bin/activate" ]; then
        echo -e "${RED}  ERRO: Phoenix não instalado. Execute sem --start primeiro.${NC}"
        exit 1
    fi

    activate_venv

    # Variáveis de ambiente
    export PHOENIX_PORT="$PORT"
    export PHOENIX_TELEMETRY_ENABLED="false"
    if [ "$AIR_GAPPED" = true ]; then
        export PHOENIX_ALLOW_EXTERNAL_RESOURCES="false"
    fi

    # Iniciar em background
    echo -e "  Iniciando Phoenix na porta ${PORT}..."
    nohup python3 -m phoenix.server.main serve > "$LOG_FILE" 2>&1 &
    local_pid=$!
    echo "$local_pid" > "$PID_FILE"

    # Aguardar startup
    echo -e "${GRAY}    Aguardando startup (max 15s)...${NC}"
    for i in $(seq 1 15); do
        if curl -s "http://localhost:${PORT}" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✓ Phoenix iniciado (PID ${local_pid})${NC}"
            echo -e "${GRAY}    UI: http://localhost:${PORT}${NC}"
            echo -e "${GRAY}    OTLP: http://localhost:4317 (gRPC)${NC}"
            echo ""
            exit 0
        fi
        sleep 1
    done

    echo -e "${YELLOW}  AVISO: Phoenix pode estar demorando para iniciar.${NC}"
    echo -e "${GRAY}    Verifique: tail -f ${LOG_FILE}${NC}"
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Ação: Install (default)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "  [1/3] Preparando ambiente Python..."

mkdir -p "$PHOENIX_DIR"

# Verificar Python
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}  ERRO: Python 3 não encontrado.${NC}"
    echo -e "${GRAY}    Instale: sudo apt install python3 python3-venv${NC}"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo -e "${GREEN}    OK: ${PYTHON_VERSION}${NC}"

# Criar/atualizar venv
if [ ! -f "${VENV_DIR}/bin/activate" ] || [ "$FORCE_REINSTALL" = true ]; then
    echo -e "${GRAY}    Criando virtualenv em ${VENV_DIR}...${NC}"
    python3 -m venv "$VENV_DIR"
fi

activate_venv

# Atualizar pip
pip install --quiet --upgrade pip

echo ""
echo -e "  [2/3] Instalando Arize Phoenix + dependências OTEL..."

# Instalar Phoenix e OpenTelemetry
pip install --quiet \
    "arize-phoenix[server]" \
    "opentelemetry-api" \
    "opentelemetry-sdk" \
    "opentelemetry-exporter-otlp-proto-grpc" \
    "opentelemetry-semantic-conventions"

PHOENIX_VERSION=$(python3 -c "import phoenix; print(phoenix.__version__)" 2>/dev/null || echo "instalado")
echo -e "${GREEN}    OK: Phoenix ${PHOENIX_VERSION}${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# Etapa 3: Configurar variáveis de ambiente
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  [3/3] Configurando variáveis de ambiente..."

# Criar arquivo de configuração de ambiente
ENV_FILE="${PHOENIX_DIR}/phoenix.env"
cat > "$ENV_FILE" << EOF
# Arize Phoenix — Variáveis de Ambiente
# Gerado por setup-phoenix.sh em $(date -Iseconds)

# Porta do servidor web
PHOENIX_PORT=${PORT}

# Desabilitar telemetria da Arize (privacidade corporativa)
PHOENIX_TELEMETRY_ENABLED=false

# Modo air-gapped (sem Google Fonts, sem CDN externo)
PHOENIX_ALLOW_EXTERNAL_RESOURCES=false

# Provedor LLM para Playground (apenas Ollama local)
PHOENIX_ALLOWED_PROVIDERS=OLLAMA

# OTLP Collector endpoint (para mcp-proxy-logger.py)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
EOF

echo -e "${GREEN}    OK: Configuração salva em ${ENV_FILE}${NC}"

# Adicionar source no shell RC se não existir
SHELL_RC="${HOME}/.bashrc"
if [ -f "${HOME}/.zshrc" ] && [ "$SHELL" = "/bin/zsh" ]; then
    SHELL_RC="${HOME}/.zshrc"
fi

MARKER="# Arize Phoenix environment"
if ! grep -q "$MARKER" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << EOF

${MARKER}
if [ -f "${ENV_FILE}" ]; then
    set -a; source "${ENV_FILE}"; set +a
fi
EOF
    echo -e "${GRAY}    Adicionado ao ${SHELL_RC}${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  INSTALAÇÃO CONCLUÍDA COM SUCESSO                           ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Componente:  Arize Phoenix (Agent Observability)            ║${NC}"
echo -e "${GREEN}║  Versão:      ${PHOENIX_VERSION}                            ║${NC}"
echo -e "${GREEN}║  Venv:        ${VENV_DIR}                                   ║${NC}"
echo -e "${GREEN}║  Config:      ${ENV_FILE}                                   ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Para iniciar:                                              ║${NC}"
echo -e "${GREEN}║    ./scripts/setup-phoenix.sh --start --air-gapped          ║${NC}"
echo -e "${GREEN}║    ou: make start-phoenix                                   ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Para parar:                                                ║${NC}"
echo -e "${GREEN}║    ./scripts/setup-phoenix.sh --stop                        ║${NC}"
echo -e "${GREEN}║    ou: make stop-phoenix                                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
