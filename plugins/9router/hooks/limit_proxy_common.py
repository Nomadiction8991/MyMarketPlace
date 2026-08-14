#!/usr/bin/env python3
"""Utilitários compartilhados do plugin 9router (fallback de provider).

Endpoint configurável via NINEROUTER_URL (default https://9router.anvy.com.br).
Token lido de NINEROUTER_KEY > CLAUDE_LIMIT_PROXY_AUTH_TOKEN > arquivo de
token (600), em runtime — nada hardcoded.
"""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
from pathlib import Path

DEFAULT_9ROUTER_URL = "https://9router.anvy.com.br"
TOKEN_ENV = "CLAUDE_LIMIT_PROXY_AUTH_TOKEN"
NINEROUTER_KEY_ENV = "NINEROUTER_KEY"
CLAUDE_TOKEN_PATH = Path.home() / ".claude" / "limit-proxy-token"
OPENCODE_TOKEN_PATH = Path.home() / ".local" / "share" / "opencode" / "secrets" / "9router-token"


def ninerouter_base() -> str:
    url = (os.environ.get("NINEROUTER_URL") or "").strip().rstrip("/")
    if not url:
        url = DEFAULT_9ROUTER_URL
    if url.endswith("/v1"):
        url = url[: -3].rstrip("/")
    return url


def managed_env() -> dict[str, str]:
    base = f"{ninerouter_base()}/v1"
    return {
        "ANTHROPIC_BASE_URL": base,
        "ANTHROPIC_DEFAULT_FABLE_MODEL": "claude-fable",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku",
    }


MANAGED_ENV = managed_env()
MANAGED_KEYS = sorted([*MANAGED_ENV.keys(), "ANTHROPIC_AUTH_TOKEN", "NINEROUTER_URL", "NINEROUTER_KEY"])


def get_token() -> str | None:
    for source in (NINEROUTER_KEY_ENV, TOKEN_ENV):
        token = os.environ.get(source, "").strip()
        if token:
            return token
    for path in (OPENCODE_TOKEN_PATH, CLAUDE_TOKEN_PATH):
        try:
            stat = path.stat()
            if stat.st_uid != os.getuid() or stat.st_mode & 0o077:
                continue
            token = path.read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            continue
        if token:
            return token
    return None


def session_id_from_transcript(transcript_path: str | None) -> str | None:
    if not transcript_path:
        return None
    name = Path(transcript_path).name
    if name.endswith(".jsonl"):
        name = name[: -len(".jsonl")]
    return name or None


def open_terminal(cwd: str | None, normal_provider: bool = False, pid_file: str | None = None, session_id: str | None = None) -> int | None:
    if os.environ.get("CLAUDE_LIMIT_PROXY_OPEN_TERMINAL", "1") not in {"1", "true", "yes"}:
        return None
    workdir = cwd if cwd and Path(cwd).is_dir() else str(Path.cwd())
    pid_prefix = f"printf '%s' $$ > {shlex.quote(pid_file)}; " if pid_file else ""
    resume = f" --resume {shlex.quote(session_id)}" if session_id else ""
    claude_command = (
        f"{pid_prefix}trap 'kill -TERM 0 2>/dev/null || true' TERM; "
        f"CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1 claude{resume}; exec bash"
    )
    process_env = os.environ.copy()
    if normal_provider:
        process_env = {key: value for key, value in process_env.items() if not key.startswith("ANTHROPIC_")}
    terminals = [
        ("x-terminal-emulator", ["x-terminal-emulator", "-e", "bash", "-lc", f"cd {shlex.quote(workdir)} && {claude_command}"]),
        ("gnome-terminal", ["gnome-terminal", "--working-directory", workdir, "--", "bash", "-lc", claude_command]),
        ("konsole", ["konsole", "--workdir", workdir, "-e", "bash", "-lc", claude_command]),
        ("xfce4-terminal", ["xfce4-terminal", "--working-directory", workdir, "--command", f"bash -lc {shlex.quote(claude_command)}"]),
    ]
    for binary, command in terminals:
        if shutil.which(binary):
            try:
                process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, env=process_env)
                return process.pid
            except OSError:
                continue
    return None


def maybe_open_terminal(cwd: str | None, normal_provider: bool = False) -> bool:
    return open_terminal(cwd, normal_provider) is not None
