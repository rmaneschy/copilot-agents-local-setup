# ═══════════════════════════════════════════════════════════════════════════════
# Copilot Agents Local Setup — Makefile Orquestrador
# ═══════════════════════════════════════════════════════════════════════════════
#
# Ponto de entrada unificado para instalação e operação do ambiente de agentes
# autônomos GitHub Copilot. Detecta o sistema operacional automaticamente e
# executa o script correto (.sh para Linux/macOS, .ps1 para Windows/Git Bash).
#
# Uso:
#   make install          — Instalação completa (codebase-memory + serena + phoenix)
#   make help             — Lista todos os targets disponíveis
#
# Requisitos:
#   Linux/macOS: make (pré-instalado), bash, curl
#   Windows:     make via Git Bash (git-scm.com) ou scoop install make
#
# ═══════════════════════════════════════════════════════════════════════════════

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ─────────────────────────────────────────────────────────────────────────────
# Detecção de OS
# ─────────────────────────────────────────────────────────────────────────────
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)
ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
    OS := windows
else ifeq ($(findstring MSYS,$(UNAME_S)),MSYS)
    OS := windows
else ifeq ($(findstring CYGWIN,$(UNAME_S)),CYGWIN)
    OS := windows
else ifeq ($(UNAME_S),Linux)
    OS := linux
else ifeq ($(UNAME_S),Darwin)
    OS := macos
else
    OS := windows
endif

# ─────────────────────────────────────────────────────────────────────────────
# Diretórios
# ─────────────────────────────────────────────────────────────────────────────
SCRIPTS_DIR := scripts
WORKSPACE   ?= $(HOME)/workspace

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
define run_script
	@if [ "$(OS)" = "linux" ] || [ "$(OS)" = "macos" ]; then \
		bash $(SCRIPTS_DIR)/$(1).sh $(2); \
	else \
		powershell -ExecutionPolicy Bypass -File $(SCRIPTS_DIR)/$(1).ps1 $(2); \
	fi
endef

define header
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║  Copilot Agents Local Setup                                 ║"
	@echo "║  OS detectado: $(OS)                                        ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
endef

# ═══════════════════════════════════════════════════════════════════════════════
# TARGETS PRINCIPAIS
# ═══════════════════════════════════════════════════════════════════════════════

.PHONY: help install install-code-search install-code-navigation install-observability \
        index health status start-phoenix stop-phoenix uninstall clean

## help: Exibe esta mensagem de ajuda
help:
	@echo ""
	@echo "Copilot Agents Local Setup — Targets Disponíveis"
	@echo "════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  INSTALAÇÃO"
	@echo "  ──────────────────────────────────────────────────────────────"
	@echo "  make install                 Instalação completa (todos os componentes)"
	@echo "  make install-code-search     Instala code-search (codebase-memory-mcp)"
	@echo "  make install-code-navigation Instala code-navigation (Serena MCP)"
	@echo "  make install-observability   Instala observabilidade (Arize Phoenix)"
	@echo ""
	@echo "  OPERAÇÃO"
	@echo "  ──────────────────────────────────────────────────────────────"
	@echo "  make index                   Indexa todos os repos do workspace"
	@echo "  make index WORKSPACE=/path   Indexa workspace específico"
	@echo "  make health                  Verifica saúde de todos os componentes"
	@echo "  make status                  Status dos serviços (Phoenix, Ollama)"
	@echo ""
	@echo "  OBSERVABILIDADE"
	@echo "  ──────────────────────────────────────────────────────────────"
	@echo "  make start-phoenix           Inicia o servidor Phoenix (localhost:6006)"
	@echo "  make stop-phoenix            Para o servidor Phoenix"
	@echo ""
	@echo "  MANUTENÇÃO"
	@echo "  ──────────────────────────────────────────────────────────────"
	@echo "  make uninstall               Remove todos os componentes instalados"
	@echo "  make clean                   Remove índices e caches locais"
	@echo ""
	@echo "  VARIÁVEIS"
	@echo "  ──────────────────────────────────────────────────────────────"
	@echo "  WORKSPACE=$(WORKSPACE)"
	@echo "  OS=$(OS)"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Instalação
# ─────────────────────────────────────────────────────────────────────────────

## install: Instalação completa de todos os componentes
install: install-code-search install-code-navigation install-observability
	$(call header)
	@echo "  ✓ Instalação completa finalizada."
	@echo ""
	@echo "  Próximos passos:"
	@echo "    1. Reinicie o IntelliJ IDEA"
	@echo "    2. Verifique os MCP servers em Copilot Chat → Tools"
	@echo "    3. Execute: make index"
	@echo "    4. Execute: make health"
	@echo ""

## install-code-search: Instala o codebase-memory-mcp (knowledge graph + busca semântica)
install-code-search:
	$(call header)
	@echo "  [code-search] Instalando codebase-memory-mcp..."
	@echo ""
	$(call run_script,setup-codebase-memory,--SkipIndex)

## install-code-navigation: Instala o Serena MCP (navegação LSP determinística)
install-code-navigation:
	$(call header)
	@echo "  [code-navigation] Instalando Serena MCP..."
	@echo ""
	$(call run_script,setup-serena)

## install-observability: Instala o Arize Phoenix (tracing de decisões dos agentes)
install-observability:
	$(call header)
	@echo "  [observability] Instalando Arize Phoenix..."
	@echo ""
	$(call run_script,setup-phoenix)

# ─────────────────────────────────────────────────────────────────────────────
# Operação
# ─────────────────────────────────────────────────────────────────────────────

## index: Indexa todos os repositórios do workspace recursivamente
index:
	$(call header)
	@echo "  [index] Indexando repositórios em $(WORKSPACE)..."
	@echo ""
	$(call run_script,index-workspace,-Path $(WORKSPACE))

## health: Verifica a saúde de todos os componentes instalados
health:
	$(call header)
	@echo "  [health] Verificando componentes..."
	@echo ""
	$(call run_script,health-check)

## status: Exibe status dos serviços em execução
status:
	$(call header)
	@echo "  [status] Verificando serviços..."
	@echo ""
	@if [ "$(OS)" = "linux" ] || [ "$(OS)" = "macos" ]; then \
		echo "  Phoenix:"; \
		if [ -f "$$HOME/.phoenix/phoenix.pid" ] && kill -0 $$(cat "$$HOME/.phoenix/phoenix.pid") 2>/dev/null; then \
			echo "    ✓ Rodando (PID $$(cat $$HOME/.phoenix/phoenix.pid)) — http://localhost:6006"; \
		else \
			echo "    ✗ Parado"; \
		fi; \
		echo "  Ollama:"; \
		if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then \
			echo "    ✓ Rodando — http://localhost:11434"; \
		else \
			echo "    ✗ Parado"; \
		fi; \
	else \
		powershell -ExecutionPolicy Bypass -Command " \
			Write-Host '  Phoenix:'; \
			if (Test-Path '$$env:USERPROFILE\.phoenix\phoenix.pid') { \
				$$pid = Get-Content '$$env:USERPROFILE\.phoenix\phoenix.pid'; \
				if (Get-Process -Id $$pid -ErrorAction SilentlyContinue) { \
					Write-Host \"    OK Rodando (PID $$pid) - http://localhost:6006\" -ForegroundColor Green; \
				} else { Write-Host '    X Parado' -ForegroundColor Red; } \
			} else { Write-Host '    X Parado' -ForegroundColor Red; } \
			Write-Host '  Ollama:'; \
			try { Invoke-WebRequest -Uri 'http://localhost:11434/api/tags' -UseBasicParsing -TimeoutSec 2 | Out-Null; \
				Write-Host '    OK Rodando - http://localhost:11434' -ForegroundColor Green; \
			} catch { Write-Host '    X Parado' -ForegroundColor Red; } \
		"; \
	fi
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Observabilidade
# ─────────────────────────────────────────────────────────────────────────────

## start-phoenix: Inicia o servidor Phoenix para visualização de traces
start-phoenix:
	$(call header)
	@echo "  [phoenix] Iniciando servidor..."
	@echo ""
	$(call run_script,setup-phoenix,-Start -AirGapped)

## stop-phoenix: Para o servidor Phoenix
stop-phoenix:
	$(call header)
	@echo "  [phoenix] Parando servidor..."
	@echo ""
	$(call run_script,setup-phoenix,-Stop)

# ─────────────────────────────────────────────────────────────────────────────
# Manutenção
# ─────────────────────────────────────────────────────────────────────────────

## uninstall: Remove todos os componentes instalados
uninstall:
	$(call header)
	@echo "  [uninstall] Removendo componentes..."
	@echo ""
	$(call run_script,setup-codebase-memory,-Uninstall)
	@echo ""
	@echo "  ✓ Componentes removidos."
	@echo "  Nota: Serena e Phoenix (pip packages) devem ser removidos manualmente:"
	@echo "    pip uninstall serena-agent arize-phoenix"
	@echo ""

## clean: Remove índices e caches locais (não remove binários)
clean:
	$(call header)
	@echo "  [clean] Removendo caches e índices..."
	@echo ""
	@if [ "$(OS)" = "linux" ] || [ "$(OS)" = "macos" ]; then \
		rm -rf "$$HOME/.phoenix/phoenix.db" 2>/dev/null; \
		echo "  ✓ Cache Phoenix removido"; \
		find "$(WORKSPACE)" -name ".codebase-memory" -type d -exec rm -rf {} + 2>/dev/null; \
		echo "  ✓ Índices codebase-memory removidos de $(WORKSPACE)"; \
	else \
		powershell -ExecutionPolicy Bypass -Command " \
			Remove-Item -Recurse -Force '$$env:USERPROFILE\.phoenix\phoenix.db' -ErrorAction SilentlyContinue; \
			Write-Host '  OK Cache Phoenix removido'; \
			Get-ChildItem -Path '$(WORKSPACE)' -Directory -Recurse -Filter '.codebase-memory' | Remove-Item -Recurse -Force; \
			Write-Host '  OK Indices codebase-memory removidos'; \
		"; \
	fi
	@echo ""
