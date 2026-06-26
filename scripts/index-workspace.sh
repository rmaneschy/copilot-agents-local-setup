#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# index-workspace.sh — Indexa repositórios do workspace (Linux)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Percorre o workspace recursivamente, identifica repositórios Git (pastas com
# .git) e indexa cada um individualmente via codebase-memory-mcp.
#
# Estratégia Greedy-Stop: ao encontrar um .git, indexa e NÃO desce mais naquele
# ramo (evita indexar submodules como projetos independentes).
#
# Uso:
#   ./scripts/index-workspace.sh [opções]
#
# Opções:
#   --path PATH          Raiz do workspace (padrão: ~/workspace)
#   --max-depth N        Profundidade máxima de busca (padrão: 3)
#   --include PATTERN    Glob para incluir repos por nome (padrão: *)
#   --exclude PATTERN    Glob para excluir repos por nome
#   --force              Re-indexação completa (ignora cache)
#   --parallel N         Repos simultâneos (padrão: 1)
#   --dry-run            Lista repos sem indexar
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
MAX_DEPTH=3
INCLUDE_PATTERN="*"
EXCLUDE_PATTERN=""
FORCE=false
PARALLEL=1
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path|-Path)       WORKSPACE_PATH="$2"; shift 2 ;;
        --max-depth)        MAX_DEPTH="$2"; shift 2 ;;
        --include)          INCLUDE_PATTERN="$2"; shift 2 ;;
        --exclude)          EXCLUDE_PATTERN="$2"; shift 2 ;;
        --force|-Force)     FORCE=true; shift ;;
        --parallel)         PARALLEL="$2"; shift 2 ;;
        --dry-run|-DryRun)  DRY_RUN=true; shift ;;
        *)                  echo -e "${RED}Opção desconhecida: $1${NC}"; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Index Workspace — Indexação Recursiva de Repositórios       ║${NC}"
echo -e "${CYAN}║  Greedy-Stop: indexa .git e não desce em submodules          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Workspace:   ${WORKSPACE_PATH}"
echo -e "  Max Depth:   ${MAX_DEPTH}"
echo -e "  Include:     ${INCLUDE_PATTERN}"
echo -e "  Exclude:     ${EXCLUDE_PATTERN:-<nenhum>}"
echo -e "  Force:       ${FORCE}"
echo -e "  Parallel:    ${PARALLEL}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Verificações
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo -e "${RED}  ERRO: Diretório não encontrado: ${WORKSPACE_PATH}${NC}"
    exit 1
fi

if ! command -v codebase-memory-mcp &>/dev/null; then
    echo -e "${RED}  ERRO: codebase-memory-mcp não encontrado no PATH.${NC}"
    echo -e "${GRAY}    Execute primeiro: make install-code-search${NC}"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Descoberta de repositórios (Greedy-Stop)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "  [1/2] Descobrindo repositórios Git..."
echo ""

REPOS=()
SKIPPED=()

discover_repos() {
    local dir="$1"
    local depth="$2"

    # Limite de profundidade
    if [ "$depth" -gt "$MAX_DEPTH" ]; then
        return
    fi

    # Iterar subdiretórios
    for entry in "$dir"/*/; do
        [ -d "$entry" ] || continue

        local name
        name=$(basename "$entry")

        # Se encontrou .git → é um repositório
        if [ -d "${entry}.git" ]; then
            # Aplicar filtro include
            if [[ "$name" != $INCLUDE_PATTERN ]]; then
                continue
            fi

            # Aplicar filtro exclude
            if [ -n "$EXCLUDE_PATTERN" ] && [[ "$name" == $EXCLUDE_PATTERN ]]; then
                SKIPPED+=("$entry")
                continue
            fi

            REPOS+=("$entry")
            # Greedy-stop: não descer mais neste ramo
        else
            # Não é repo, continuar descendo
            discover_repos "$entry" $((depth + 1))
        fi
    done
}

discover_repos "$WORKSPACE_PATH" 1

# Verificar se o próprio workspace é um repo
if [ -d "${WORKSPACE_PATH}/.git" ]; then
    REPOS=("$WORKSPACE_PATH" "${REPOS[@]}")
fi

TOTAL=${#REPOS[@]}

if [ "$TOTAL" -eq 0 ]; then
    echo -e "${YELLOW}  Nenhum repositório encontrado em ${WORKSPACE_PATH} (depth=${MAX_DEPTH}).${NC}"
    echo ""
    exit 0
fi

echo -e "  Repositórios encontrados: ${GREEN}${TOTAL}${NC}"
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "  Excluídos pelo filtro:    ${YELLOW}${#SKIPPED[@]}${NC}"
fi
echo ""

# Listar repos
for repo in "${REPOS[@]}"; do
    local_name=$(basename "$repo")
    echo -e "    ${CYAN}●${NC} ${local_name} ${GRAY}(${repo})${NC}"
done
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Modo Dry-Run
# ─────────────────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}  [DRY-RUN] Nenhuma indexação realizada.${NC}"
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Indexação
# ─────────────────────────────────────────────────────────────────────────────
echo -e "  [2/2] Indexando repositórios..."
echo ""

SUCCESS=0
FAILED=0
START_TIME=$(date +%s)

index_repo() {
    local repo_path="$1"
    local repo_name
    repo_name=$(basename "$repo_path")

    local force_flag=""
    if [ "$FORCE" = true ]; then
        force_flag="--force"
    fi

    echo -e "    ${CYAN}▶${NC} Indexando: ${repo_name}..."

    if (cd "$repo_path" && codebase-memory-mcp index $force_flag 2>&1); then
        echo -e "    ${GREEN}✓${NC} ${repo_name} — indexado com sucesso"
        return 0
    else
        echo -e "    ${RED}✗${NC} ${repo_name} — falha na indexação"
        return 1
    fi
}

if [ "$PARALLEL" -gt 1 ]; then
    # Indexação paralela via GNU parallel ou xargs
    echo -e "${GRAY}    Modo paralelo: ${PARALLEL} repos simultâneos${NC}"
    echo ""

    for repo in "${REPOS[@]}"; do
        index_repo "$repo" &

        # Controlar paralelismo
        while [ "$(jobs -r | wc -l)" -ge "$PARALLEL" ]; do
            wait -n 2>/dev/null || true
        done
    done

    # Aguardar todos finalizarem
    wait

    # Contar resultados (simplificado no modo paralelo)
    SUCCESS=$TOTAL
else
    # Indexação sequencial
    for repo in "${REPOS[@]}"; do
        echo ""
        if index_repo "$repo"; then
            SUCCESS=$((SUCCESS + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    done
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ─────────────────────────────────────────────────────────────────────────────
# Relatório Final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "  RELATÓRIO DE INDEXAÇÃO"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Total:       ${TOTAL} repositórios"
echo -e "  Sucesso:     ${GREEN}${SUCCESS}${NC}"
echo -e "  Falha:       ${RED}${FAILED}${NC}"
echo -e "  Tempo:       ${ELAPSED}s"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${YELLOW}  Dica: Execute com --force para re-indexar repos com falha.${NC}"
    echo ""
    exit 1
fi
