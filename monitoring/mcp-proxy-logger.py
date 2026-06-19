#!/usr/bin/env python3
"""
MCP Proxy Logger — Intercepta chamadas entre o Copilot e MCP servers,
registrando métricas de uso em formato JSONL para análise posterior.

Funciona como um wrapper stdio: o Copilot se comunica com este proxy,
que repassa para o MCP server real e registra cada request/response.

Uso:
    python mcp-proxy-logger.py --server "serena" --command "serena" --args "--context=jb-copilot-plugin"
    python mcp-proxy-logger.py --server "local-code-rag" --command "npx" --args "mcp-vector-search"

O proxy é transparente: stdin/stdout passam intactos para o server real.
Os logs são escritos em ~/.copilot-metrics/calls.jsonl
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


# --- Configuração ---

METRICS_DIR = Path.home() / ".copilot-metrics"
CALLS_LOG = METRICS_DIR / "calls.jsonl"
ERRORS_LOG = METRICS_DIR / "errors.log"


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


class MCPProxyLogger:
    """Proxy stdio que intercepta JSON-RPC entre Copilot e MCP server."""

    def __init__(self, server_name: str, command: str, args: list):
        self.server_name = server_name
        self.command = command
        self.args = args
        self.process = None
        self.pending_requests = {}  # id -> (method, params, start_time)

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
        """Registra a resposta e calcula duração."""
        msg_id = message.get("id")

        if msg_id is not None and msg_id in self.pending_requests:
            method, params, start_time = self.pending_requests.pop(msg_id)
            duration_ms = (time.perf_counter() - start_time) * 1000

            has_error = "error" in message
            error_msg = None
            if has_error:
                error_obj = message.get("error", {})
                error_msg = error_obj.get("message", str(error_obj))

            log_call(
                server=self.server_name,
                method=method,
                params=params,
                duration_ms=duration_ms,
                success=not has_error,
                error=error_msg,
            )

    def _shutdown(self):
        """Encerra o subprocesso."""
        if self.process:
            try:
                self.process.stdin.close()
            except Exception:
                pass
            self.process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description="MCP Proxy Logger")
    parser.add_argument("--server", required=True, help="Nome do MCP server (ex: serena, local-code-rag)")
    parser.add_argument("--command", required=True, help="Comando do MCP server real")
    parser.add_argument("--args", nargs="*", default=[], help="Argumentos do MCP server")

    args = parser.parse_args()

    proxy = MCPProxyLogger(
        server_name=args.server,
        command=args.command,
        args=args.args,
    )
    proxy.start()


if __name__ == "__main__":
    main()
