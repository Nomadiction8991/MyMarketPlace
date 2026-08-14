#!/usr/bin/env python3
"""Controle manual do plugin 9router (/9router): status|on|off|aplicar|remover|token."""

from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from limit_proxy_common import MANAGED_ENV, MANAGED_KEYS, NINEROUTER_KEY_ENV, TOKEN_ENV, get_token, ninerouter_base, open_terminal


CLAUDE_DIR = Path.home() / ".claude"
SETTINGS_PATH = CLAUDE_DIR / "settings.json"
STATE_DIR = CLAUDE_DIR / "limit-proxy"
STATE_PATH = STATE_DIR / "state.json"
LOCK_PATH = STATE_DIR / "lock"
DISABLED_PATH = STATE_DIR / "disabled"
GUARD_PATH = Path(__file__).resolve().parent / "limit-proxy-guard.py"

MANUAL_RESTORE_HOURS = 5


class FileLock:
    def __enter__(self) -> "FileLock":
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        STATE_DIR.chmod(0o700)
        self.file = LOCK_PATH.open("w", encoding="utf-8")
        fcntl.flock(self.file.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        fcntl.flock(self.file.fileno(), fcntl.LOCK_UN)
        self.file.close()


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def load_state_for_write() -> dict[str, Any] | None:
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as exc:
        print(f"state.json inválido; operação cancelada para não perder o estado anterior: {exc}")
        return None
    if not isinstance(data, dict):
        print("state.json não contém um objeto JSON; operação cancelada.")
        return None
    return data


def load_settings() -> dict[str, Any] | None:
    try:
        data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as exc:
        print(f"settings.json inválido; operação cancelada para não sobrescrever sua configuração: {exc}")
        return None
    if not isinstance(data, dict):
        print("settings.json não contém um objeto JSON; operação cancelada.")
        return None
    return data


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd = os.open(path.with_suffix(path.suffix + ".tmp"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    tmp = Path(path.with_suffix(path.suffix + ".tmp"))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(body)
    tmp.replace(path)
    path.chmod(0o600)


def restore_proxy() -> bool:
    settings = load_settings()
    if settings is None:
        return False
    state = load_state_for_write()
    if state is None:
        return False
    env = settings.setdefault("env", {})
    if not isinstance(env, dict):
        return False

    changed = False
    previous_env = state.get("previous_env", {}) if isinstance(state.get("previous_env"), dict) else {}
    previous_present = state.get("previous_present", {}) if isinstance(state.get("previous_present"), dict) else {}
    for key in MANAGED_KEYS:
        was_present = key in env
        before = env.get(key)
        if previous_present.get(key):
            env[key] = previous_env.get(key)
        else:
            env.pop(key, None)
        changed = changed or was_present != (key in env) or before != env.get(key)
    before_onboarding = settings.get("hasCompletedOnboarding")
    if state.get("previous_has_completed_onboarding_present"):
        settings["hasCompletedOnboarding"] = state.get("previous_has_completed_onboarding")
    else:
        settings.pop("hasCompletedOnboarding", None)
    changed = changed or before_onboarding != settings.get("hasCompletedOnboarding")

    state["active"] = False
    state["manual_control_restored"] = True
    write_json(SETTINGS_PATH, settings)
    if changed:
        terminal_pid = open_terminal(configured_cwd(), normal_provider=True, pid_file=str(STATE_DIR / "normal-shell.pid"))
        opened = terminal_pid is not None
        state["terminal_opened_on_restore"] = opened
        if terminal_pid is not None:
            state["normal_terminal_pid"] = terminal_pid
        state["old_claude_close_scheduled_on_restore"] = maybe_close_old_claude() if opened else False
    write_json(STATE_PATH, state)
    return changed


def status() -> None:
    settings = load_settings() or {}
    state = load_json(STATE_PATH, {})
    if not isinstance(state, dict):
        state = {}
    env = settings.get("env", {}) if isinstance(settings.get("env"), dict) else {}
    proxy_set = any(key in env for key in MANAGED_KEYS)
    print("Status do 9router:")
    print(f"- Sistema: {'desativado' if DISABLED_PATH.exists() else 'ativado'}")
    print(f"- 9router no settings.json: {'aplicado' if proxy_set else 'não aplicado'}")
    print(f"- Estado ativo: {'sim' if state.get('active') else 'não'}")
    print(f"- Endpoint: {ninerouter_base()}")
    print(f"- Token salvo: {'sim' if get_token() else 'não'}")
    if state.get("reset_at"):
        print(f"- Reset registrado: {state.get('reset_at')}")
    if state.get("restore_at"):
        print(f"- Restauração registrada: {state.get('restore_at')}")


def enable() -> None:
    DISABLED_PATH.unlink(missing_ok=True)
    print("Sistema 9router ativado. O hook voltará a agir quando detectar limite.")


def configured_cwd() -> str | None:
    cwd = os.environ.get("LIMIT_PROXY_CWD", "").strip()
    return cwd if cwd and Path(cwd).is_dir() else None


def proc_comm(pid: int) -> str | None:
    try:
        with open(f"/proc/{pid}/comm", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return None


def proc_ppid(pid: int) -> int | None:
    try:
        with open(f"/proc/{pid}/status", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        return None
    return None


def find_ancestor_process(name_fragment: str) -> int | None:
    pid = os.getppid()
    current_pid = os.getpid()
    for _ in range(12):
        if pid <= 1 or pid == current_pid:
            return None
        command_name = proc_comm(pid)
        if command_name and name_fragment.lower() in command_name.lower():
            return pid
        next_pid = proc_ppid(pid)
        if not next_pid or next_pid == pid:
            return None
        pid = next_pid
    return None


def maybe_close_old_claude() -> bool:
    if os.environ.get("CLAUDE_LIMIT_PROXY_CLOSE_OLD_CLAUDE", "0") not in {"1", "true", "yes"}:
        return False
    claude_pid = find_ancestor_process("claude")
    if not claude_pid:
        return False
    try:
        subprocess.Popen(
            [sys.executable, "-c", f"import os, signal, time; time.sleep(2); os.kill({claude_pid}, signal.SIGTERM)"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except OSError:
        return False


def start_restore_worker() -> bool:
    try:
        subprocess.Popen(
            [sys.executable, str(GUARD_PATH), "--restore-wait"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except OSError:
        return False


def apply_proxy_now() -> bool:
    token = get_token()
    if not token:
        print(f"Token não encontrado. Defina {NINEROUTER_KEY_ENV} ou {TOKEN_ENV}, ou crie ~/.claude/limit-proxy-token com permissão 600.")
        return False

    settings = load_settings()
    if settings is None:
        return False
    state = load_state_for_write()
    if state is None:
        return False
    env = settings.setdefault("env", {})
    if not isinstance(env, dict):
        print("settings.env não é um objeto; 9router não aplicado.")
        return False

    now = dt.datetime.now(dt.timezone.utc)
    restore_at = now + dt.timedelta(hours=MANUAL_RESTORE_HOURS)
    if not state.get("active"):
        last_transcript_path = state.get("last_transcript_path")
        last_transcript_offset = state.get("last_transcript_offset")
        state = {
            "active": True,
            "activated_at": now.isoformat(),
            "reset_at": now.isoformat(),
            "reset_time_detected": False,
            "restore_at": restore_at.isoformat(),
            "previous_env": {key: env.get(key) for key in MANAGED_KEYS if key in env},
            "previous_present": {key: key in env for key in MANAGED_KEYS},
            "previous_has_completed_onboarding_present": "hasCompletedOnboarding" in settings,
            "previous_has_completed_onboarding": settings.get("hasCompletedOnboarding"),
            "terminal_opened_on_activation": False,
            "terminal_opened_on_restore": False,
            "old_claude_close_scheduled": False,
            "restore_worker_started": False,
            "manual_activation": True,
        }
        if isinstance(last_transcript_path, str):
            state["last_transcript_path"] = last_transcript_path
        if isinstance(last_transcript_offset, int):
            state["last_transcript_offset"] = last_transcript_offset
    else:
        if state.get("restore_at"):
            try:
                restore_at = dt.datetime.fromisoformat(str(state.get("restore_at")).replace("Z", "+00:00"))
            except ValueError:
                print("restore_at inválido no state.json; mantendo nova restauração de segurança.")
                state["restore_at"] = restore_at.isoformat()
    env.update(MANAGED_ENV)
    env["ANTHROPIC_AUTH_TOKEN"] = token
    env["NINEROUTER_URL"] = ninerouter_base()
    env["NINEROUTER_KEY"] = token
    settings["hasCompletedOnboarding"] = True
    cwd = configured_cwd()
    if cwd:
        state["cwd"] = cwd
    write_json(STATE_PATH, state)
    write_json(SETTINGS_PATH, settings)

    opened = False
    if not state.get("terminal_opened_on_activation"):
        external_pid_file = str(STATE_DIR / "external-shell.pid")
        terminal_pid = open_terminal(cwd, pid_file=external_pid_file)
        opened = terminal_pid is not None
        state["terminal_opened_on_activation"] = opened
        if terminal_pid is not None:
            state["external_terminal_pid"] = terminal_pid
            state["external_shell_pid_file"] = external_pid_file
    closed = False
    if opened and not state.get("old_claude_close_scheduled"):
        closed = maybe_close_old_claude()
        state["old_claude_close_scheduled"] = closed
    if not state.get("restore_worker_started"):
        state["restore_worker_started"] = start_restore_worker()
    write_json(STATE_PATH, state)
    extra = " Novo Claude aberto." if opened else " Reinicie o Claude para carregar o 9router."
    if closed:
        extra += " Claude antigo agendado para fechar."
    print(f"9router aplicado manualmente. Restauração de segurança registrada para {restore_at.isoformat()}.{extra}")
    return True


def disable() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_DIR.chmod(0o700)
    DISABLED_PATH.write_text("disabled\n", encoding="utf-8")
    DISABLED_PATH.chmod(0o600)
    changed = restore_proxy()
    suffix = " 9router removido do settings.json." if changed else " Nenhum 9router aplicado para remover."
    print("Sistema 9router desativado." + suffix)


def save_token_from_env() -> None:
    token = os.environ.get(NINEROUTER_KEY_ENV, "").strip() or os.environ.get(TOKEN_ENV, "").strip()
    if not token:
        print(f"Para não expor token no chat, defina {NINEROUTER_KEY_ENV} (ou {TOKEN_ENV}) no ambiente; o token será salvo em ~/.claude/limit-proxy-token com permissão 600.")
        return
    path = Path.home() / ".claude" / "limit-proxy-token"
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(token)
    tmp.replace(path)
    path.chmod(0o600)
    print("Token salvo em ~/.claude/limit-proxy-token.")


def usage() -> None:
    print("Uso: /9router [status|on|off|aplicar|remover|token]")


def main() -> None:
    action = (sys.argv[1] if len(sys.argv) > 1 else "status").lower()
    if len(sys.argv) > 2:
        usage()
        raise SystemExit("Argumentos extras não são aceitos para evitar comando acidental.")
    with FileLock():
        if action in {"status", "st"}:
            status()
        elif action in {"on", "enable", "ativar"}:
            enable()
        elif action in {"off", "disable", "desativar"}:
            disable()
        elif action in {"remover", "remove", "restore", "restaurar"}:
            changed = restore_proxy()
            print("9router removido do settings.json." if changed else "Nenhum 9router aplicado para remover.")
        elif action in {"aplicar", "apply", "usar"}:
            apply_proxy_now()
        elif action == "token":
            save_token_from_env()
        else:
            usage()
            raise SystemExit(2)


if __name__ == "__main__":
    main()