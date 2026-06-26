#!/usr/bin/env python3
"""
MCP Proxy Logger — Intercepta chamadas entre o Copilot e MCP servers,
registrando métricas de uso em formato JSONL e exportando traces via
OpenTelemetry (OTLP) para o Arize Phoenix.

Funciona como um wrapper stdio: o Copilot se comunica com este proxy,
que repassa para o MCP server real e registra cada request/response.

Uso:
    python mcp-proxy-logger.py --server "code-navigation" --command "serena" --args "--context=jb-copilot-plugin"
    python mcp-proxy-logger.py --server "code-search" --command "codebase-memory-mcp" --args ""

Modos de operação:
    - JSONL only (padrão): Registra em ~/.copilot-metrics/calls.jsonl
    - JSONL + Phoenix: Exporta traces OTEL para Phoenix (requer --phoenix)

O proxy é transparente: stdin/stdout passam intactos para o server real.
"""

import sys
import os
import json
import subprocess
import threading
import time
import argparse
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Tuple, Any


# ─────────────────────────────────────────────────────────────────────────────
# Configuração
# ─────────────────────────────────────────────────────────────────────────────

METRICS_DIR = Path.home() / ".copilot-metrics"
CALLS_LOG = METRICS_DIR / "calls.jsonl"
ERRORS_LOG = METRICS_DIR / "errors.log"

# Phoenix/OTEL defaults (podem ser sobrescritos por env vars)
PHOENIX_ENDPOINT = os.environ.get("PHOENIX_COLLECTOR_ENDPOINT", "http://localhost:6006")
PHOENIX_PROJECT = os.environ.get("PHOENIX_PROJECT_NAME", "copilot-agent-traces")


# ─────────────────────────────────────────────────────────────────────────────
# OpenTelemetry Exporter (carregamento condicional)
# ─────────────────────────────────────────────────────────────────────────────

class OTELExporter:
    """Exportador OpenTelemetry para Phoenix. Carregado sob demanda."""

    def __init__(self, endpoint: str, project_name: str, server_name: str):
        self.enabled = False
        self.server_name = server_name
        self._tracer = None
        self._session_span = None
        self._session_id = f"session-{int(time.time())}"

        try:
            from opentelemetry import trace
            from opentelemetry.sdk.trace import TracerProvider
            from opentelemetry.sdk.trace.export import BatchSpanProcessor
            from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
            from opentelemetry.sdk.resources import Resource

            resource = Resource.create({
                "service.name": f"mcp-{server_name}",
                "service.version": "1.0.0",
                "deployment.environment": "local",
                "phoenix.project.name": project_name,
            })

            exporter = OTLPSpanExporter(
                endpoint=f"{endpoint}/v1/traces",
                headers={"content-type": "application/x-protobuf"},
            )

            provider = TracerProvider(resource=resource)
            provider.add_span_processor(BatchSpanProcessor(
                exporter,
                max_queue_size=256,
                max_export_batch_size=32,
                export_timeout_millis=5000,
            ))

            trace.set_tracer_provider(provider)
            self._tracer = trace.get_tracer(
                instrumenting_module_name="mcp-proxy-logger",
                instrumenting_library_version="2.0.0",
            )
            self._provider = provider
            self.enabled = True

        except ImportError as e:
            log_error(f"OTEL não disponível (instale com setup-phoenix.ps1): {e}")
        except Exception as e:
            log_error(f"Falha ao inicializar OTEL exporter: {e}")

    def start_session(self):
        """Inicia um span de sessão (agrupa todos os tool calls)."""
        if not self.enabled:
            return
        from opentelemetry import trace
        self._session_span = self._tracer.start_span(
            name=f"mcp-session/{self.server_name}",
            attributes={
                "session.id": self._session_id,
                "mcp.server": self.server_name,
                "session.start_time": datetime.now(timezone.utc).isoformat(),
            },
        )
        self._session_context = trace.context_api.set_value(
            trace.context_api._SPAN_KEY if hasattr(trace.context_api, '_SPAN_KEY')
            else "current-span",
            self._session_span,
        )

    def trace_tool_call(
        self,
        method: str,
        tool_name: str,
        params: dict,
        duration_ms: float,
        success: bool,
        error: Optional[str] = None,
        response_summary: Optional[str] = None,
    ):
        """Cria um span para uma tool call individual."""
        if not self.enabled:
            return

        from opentelemetry.trace import StatusCode

        # Criar span como filho da sessão
        context = None
        if self._session_span:
            from opentelemetry import trace as trace_mod
            from opentelemetry import context as context_mod
            ctx = trace_mod.set_span_in_context(self._session_span)
            context = ctx

        span = self._tracer.start_span(
            name=f"{self.server_name}/{tool_name}",
            context=context,
            attributes={
                "mcp.server": self.server_name,
                "mcp.method": method,
                "mcp.tool": tool_name,
                "mcp.params": summarize_params(params),
                "mcp.duration_ms": duration_ms,
                "mcp.success": success,
                # OpenInference semantic conventions
                "openinference.span.kind": "TOOL",
                "tool.name": tool_name,
                "tool.description": f"MCP tool call via {self.server_name}",
                "input.value": summarize_params(params),
            },
        )

        if response_summary:
            span.set_attribute("output.value", response_summary)

        if error:
            span.set_attribute("mcp.error", error)
            span.set_status(StatusCode.ERROR, error)
        else:
            span.set_status(StatusCode.OK)

        # Definir duração explicitamente via end_time
        span.end()

    def end_session(self):
        """Finaliza o span de sessão."""
        if not self.enabled:
            return
        if self._session_span:
            self._session_span.end()
        # Flush pendentes
        try:
            self._provider.force_flush(timeout_millis=5000)
        except Exception:
            pass

    def shutdown(self):
        """Encerra o exporter e faz flush final."""
        if not self.enabled:
            return
        self.end_session()
        try:
            self._provider.shutdown()
        except Exception:
            pass


# ─────────────────────────────────────────────────────────────────────────────
# Funções de Logging (JSONL)
# ─────────────────────────────────────────────────────────────────────────────

def ensure_metrics_dir():
    """Cria o diretório de métricas se não existir."""
    METRICS_DIR.mkdir(parents=True, exist_ok=True)


def log_call(server: str, method: str, params: dict, duration_ms: float, success: bool, error: str = None):
    """Registra uma chamada no arquivo JSONL."""
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "server": server,
        "method": method,
        "tool": extract_tool_name(method, params),
        "params_summary": summarize_params(params),
        "duration_ms": round(duration_ms, 2),
        "success": success,
        "error": error,
    }
    try:
        with open(CALLS_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        log_error(f"Failed to write call log: {e}")


def log_error(message: str):
    """Registra erros internos do proxy."""
    try:
        with open(ERRORS_LOG, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().isoformat()}] {message}\n")
    except Exception:
        pass


def extract_tool_name(method: str, params: dict) -> str:
    """Extrai o nome da tool a partir do método e parâmetros."""
    if method == "tools/call":
        return params.get("name", "unknown")
    elif method == "tools/list":
        return "_list_tools"
    elif method == "resources/read":
        return f"_resource:{params.get('uri', 'unknown')}"
    return method


def summarize_params(params: dict) -> str:
    """Cria um resumo compacto dos parâmetros (max 200 chars)."""
    if not params:
        return ""
    try:
        summary = json.dumps(params, ensure_ascii=False)
        if len(summary) > 200:
            return summary[:197] + "..."
        return summary
    except Exception:
        return str(params)[:200]


def summarize_response(message: dict) -> Optional[str]:
    """Cria um resumo compacto da resposta (max 500 chars)."""
    result = message.get("result")
    if not result:
        return None
    try:
        summary = json.dumps(result, ensure_ascii=False)
        if len(summary) > 500:
            return summary[:497] + "..."
        return summary
    except Exception:
        return str(result)[:500]


# ─────────────────────────────────────────────────────────────────────────────
# MCP Proxy
# ─────────────────────────────────────────────────────────────────────────────

class MCPProxyLogger:
    """Proxy stdio que intercepta JSON-RPC entre Copilot e MCP server."""

    def __init__(self, server_name: str, command: str, args: list, otel_exporter: Optional[OTELExporter] = None):
        self.server_name = server_name
        self.command = command
        self.args = args
        self.process = None
        self.pending_requests: Dict[Any, Tuple[str, dict, float]] = {}
        self.otel = otel_exporter

    def start(self):
        """Inicia o MCP server como subprocesso."""
        ensure_metrics_dir()

        full_command = [self.command] + self.args

        try:
            self.process = subprocess.Popen(
                full_command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                bufsize=0,
            )
        except FileNotFoundError:
            log_error(f"Command not found: {full_command}")
            sys.exit(1)

        # Iniciar sessão OTEL
        if self.otel:
            self.otel.start_session()

        # Thread para ler stderr do server (não bloqueia)
        stderr_thread = threading.Thread(target=self._drain_stderr, daemon=True)
        stderr_thread.start()

        # Thread para ler stdout do server e repassar ao Copilot
        stdout_thread = threading.Thread(target=self._read_server_stdout, daemon=True)
        stdout_thread.start()

        # Loop principal: ler stdin do Copilot e repassar ao server
        self._read_copilot_stdin()

    def _read_copilot_stdin(self):
        """Lê mensagens JSON-RPC do Copilot (stdin) e repassa ao server."""
        try:
            for line in sys.stdin.buffer:
                if not line:
                    break

                # Tenta parsear como JSON-RPC para logging
                try:
                    message = json.loads(line.decode("utf-8").strip())
                    self._handle_request(message)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    pass

                # Repassa intacto para o server
                if self.process and self.process.stdin:
                    self.process.stdin.write(line)
                    self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            pass
        finally:
            self._shutdown()

    def _read_server_stdout(self):
        """Lê respostas do server (stdout) e repassa ao Copilot."""
        try:
            for line in self.process.stdout:
                if not line:
                    break

                # Tenta parsear como JSON-RPC para logging
                try:
                    message = json.loads(line.decode("utf-8").strip())
                    self._handle_response(message)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    pass

                # Repassa intacto para o Copilot
                sys.stdout.buffer.write(line)
                sys.stdout.buffer.flush()
        except (BrokenPipeError, OSError):
            pass

    def _drain_stderr(self):
        """Drena stderr do server para evitar deadlock."""
        try:
            for line in self.process.stderr:
                log_error(f"[{self.server_name}] {line.decode('utf-8', errors='replace').strip()}")
        except (BrokenPipeError, OSError):
            pass

    def _handle_request(self, message: dict):
        """Registra um request JSON-RPC pendente."""
        msg_id = message.get("id")
        method = message.get("method", "")
        params = message.get("params", {})

        if msg_id is not None and method:
            self.pending_requests[msg_id] = (method, params, time.perf_counter())

    def _handle_response(self, message: dict):
        """Registra a resposta, calcula duração e exporta trace."""
        msg_id = message.get("id")

        if msg_id is not None and msg_id in self.pending_requests:
            method, params, start_time = self.pending_requests.pop(msg_id)
            duration_ms = (time.perf_counter() - start_time) * 1000

            has_error = "error" in message
            error_msg = None
            if has_error:
                error_obj = message.get("error", {})
                error_msg = error_obj.get("message", str(error_obj))

            tool_name = extract_tool_name(method, params)

            # Log JSONL (sempre ativo)
            log_call(
                server=self.server_name,
                method=method,
                params=params,
                duration_ms=duration_ms,
                success=not has_error,
                error=error_msg,
            )

            # Export OTEL para Phoenix (se habilitado)
            if self.otel:
                self.otel.trace_tool_call(
                    method=method,
                    tool_name=tool_name,
                    params=params,
                    duration_ms=duration_ms,
                    success=not has_error,
                    error=error_msg,
                    response_summary=summarize_response(message),
                )

    def _shutdown(self):
        """Encerra o subprocesso e finaliza OTEL."""
        if self.otel:
            self.otel.shutdown()
        if self.process:
            try:
                self.process.stdin.close()
            except Exception:
                pass
            self.process.wait(timeout=5)


# ─────────────────────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="MCP Proxy Logger — Intercepta e registra chamadas MCP com suporte a Phoenix/OTEL",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  # Modo JSONL only (padrão)
  python mcp-proxy-logger.py --server "code-navigation" --command "serena"

  # Modo JSONL + Phoenix (exporta traces OTEL)
  python mcp-proxy-logger.py --server "code-search" --command "codebase-memory-mcp" --phoenix

  # Phoenix em endpoint customizado
  python mcp-proxy-logger.py --server "code-navigation" --command "serena" --phoenix --phoenix-endpoint "http://localhost:9090"
        """,
    )
    parser.add_argument("--server", required=True, help="Nome lógico do MCP server (ex: code-navigation, code-search)")
    parser.add_argument("--command", required=True, help="Comando do MCP server real")
    parser.add_argument("--args", nargs="*", default=[], help="Argumentos do MCP server")
    parser.add_argument("--phoenix", action="store_true", help="Habilita exportação de traces para Phoenix via OTEL")
    parser.add_argument("--phoenix-endpoint", default=PHOENIX_ENDPOINT, help=f"Endpoint do Phoenix (padrão: {PHOENIX_ENDPOINT})")
    parser.add_argument("--phoenix-project", default=PHOENIX_PROJECT, help=f"Nome do projeto no Phoenix (padrão: {PHOENIX_PROJECT})")

    args = parser.parse_args()

    # Inicializar OTEL exporter se --phoenix
    otel_exporter = None
    if args.phoenix:
        otel_exporter = OTELExporter(
            endpoint=args.phoenix_endpoint,
            project_name=args.phoenix_project,
            server_name=args.server,
        )
        if otel_exporter.enabled:
            log_error(f"[INFO] OTEL exporter habilitado → {args.phoenix_endpoint}")
        else:
            log_error("[WARN] OTEL exporter não pôde ser inicializado. Continuando em modo JSONL only.")
            otel_exporter = None

    proxy = MCPProxyLogger(
        server_name=args.server,
        command=args.command,
        args=args.args,
        otel_exporter=otel_exporter,
    )
    proxy.start()


if __name__ == "__main__":
    main()
