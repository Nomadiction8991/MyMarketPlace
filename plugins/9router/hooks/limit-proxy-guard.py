#!/usr/bin/env python3
"""Claude Code hook: troca automática do provider para o 9router após avisos de limite.

Roda em UserPromptSubmit e Stop. Varre mensagens recentes do transcript, aplica
um bloco ANTHROPIC_* gerenciado quando um limite é detectado e restaura o
settings anterior depois do horário de reset + janela de graça.
"""

from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from limit_proxy_common import MANAGED_ENV, MANAGED_KEYS, NINEROUTER_KEY_ENV, TOKEN_ENV, get_token, ninerouter_base, open_terminal, session_id_from_transcript


HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
SETTINGS_PATH = CLAUDE_DIR / "settings.json"
STATE_DIR = CLAUDE_DIR / "limit-proxy"
STATE_PATH = STATE_DIR / "state.json"
LOCK_PATH = STATE_DIR / "lock"
DISABLED_PATH = STATE_DIR / "disabled"

RESTORE_GRACE_MINUTES = 15
RESET_FALLBACK_HOURS = 5
SCAN_BYTES = 250_000
BACKGROUND_ARG = "--restore-wait"
CONTROL_COMMAND = "/9router"

LIMIT_PATTERNS = [
    r"you(?:'|’)ve hit (?:your )?(?:usage|message|session) limit",
    r"hit (?:your )?(?:usage|message|session) limit",
    r"usage limit (?:reached|exceeded)",
    r"rate limit (?:reached|exceeded)",
    r"message limit (?:reached|exceeded)",
    r"session limit (?:reached|exceeded)",
    r"approach(?:ing)? (?:your )?(?:usage|message|session) limit",
    r"near (?:your )?(?:usage|message|session) limit",
    r"limite (?:de uso|da sess(?:a|ã)o|de mensagens).*(?:atingido|excedido)",
    r"(?:perto|prestes?) de atingir .*limite",
]


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_iso(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def emit(message: str, suppress: bool = False) -> None:
    print(json.dumps({"continue": True, "suppressOutput": suppress, "systemMessage": message, "reason": message}))


def emit_and_stop(message: str) -> None:
    print(json.dumps({"continue": False, "suppressOutput": False, "decision": "block", "reason": message, "systemMessage": message}))


def user_prompt(input_data: dict[str, Any]) -> str:
    value = input_data.get("user_prompt") or input_data.get("prompt")
    return value if isinstance(value, str) else ""


def hook_event(input_data: dict[str, Any]) -> str:
    value = input_data.get("hook_event_name")
    return value if isinstance(value, str) else ""


def maybe_handle_control_command(input_data: dict[str, Any]) -> bool:
    prompt = user_prompt(input_data).strip()
    if prompt != CONTROL_COMMAND and not prompt.startswith(CONTROL_COMMAND + " "):
        return False
    mark_transcript_seen(input_data)
    args = prompt[len(CONTROL_COMMAND):].strip().split()
    env = os.environ.copy()
    cwd = hook_string(input_data, "cwd")
    if cwd:
        env["LIMIT_PROXY_CWD"] = cwd
    try:
        result = subprocess.run(
            [sys.executable, str(Path(__file__).resolve().parent / "limit-proxy-control.py"), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
            env=env,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        emit_and_stop(f"9router: falha ao executar comando de controle: {exc}")
        return True

    output = (result.stdout or result.stderr or "Comando executado sem saída.").strip()
    if result.returncode == 0:
        emit_and_stop(f"9router:\n{output}")
    else:
        emit_and_stop(f"9router: comando não concluído.\n{output}")
    return True


def mark_transcript_seen(input_data: dict[str, Any]) -> None:
    transcript_path = hook_string(input_data, "transcript_path")
    if not transcript_path:
        return
    path = Path(transcript_path)
    try:
        size = path.stat().st_size
    except OSError:
        return
    with FileLock():
        state = load_json(STATE_PATH, {})
        if not isinstance(state, dict):
            state = {}
        state["last_transcript_path"] = transcript_path
        state["last_transcript_offset"] = size
        write_json(STATE_PATH, state)


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as exc:
        emit(f"9router: JSON inválido em {path}: {exc}")
        sys.exit(0)


def load_settings() -> dict[str, Any] | None:
    settings = load_json(SETTINGS_PATH, {})
    if not isinstance(settings, dict):
        emit("9router: settings.json não contém um objeto JSON; operação cancelada.")
        return None
    return settings


def load_state_for_write() -> dict[str, Any] | None:
    state = load_json(STATE_PATH, {})
    if not isinstance(state, dict):
        emit("9router: state.json não contém um objeto JSON; operação cancelada para não perder estado.")
        return None
    return state


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sensitive = path in {STATE_PATH, SETTINGS_PATH}
    if path == STATE_PATH:
        path.parent.chmod(0o700)
    tmp = path.with_suffix(path.suffix + ".tmp")
    body = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if sensitive:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(body)
    else:
        tmp.write_text(body, encoding="utf-8")
    tmp.replace(path)
    if sensitive:
        path.chmod(0o600)


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


def hook_string(input_data: dict[str, Any], key: str) -> str | None:
    value = input_data.get(key)
    return value if isinstance(value, str) and value else None


def role_from_jsonl(row: dict[str, Any]) -> str | None:
    if isinstance(row.get("message"), dict):
        role = row["message"].get("role")
        if isinstance(role, str):
            return role
    role = row.get("role") or row.get("type")
    return role if isinstance(role, str) else None


def text_from_json(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(text_from_json(item) for item in value)
    if isinstance(value, dict):
        parts = []
        for key in ("text", "content", "message", "result", "summary"):
            if key in value:
                parts.append(text_from_json(value[key]))
        return "\n".join(part for part in parts if part)
    return ""


def recent_non_user_transcript_text(transcript_path: str | None, state: dict[str, Any], event_name: str = "") -> tuple[str, int | None]:
    if not transcript_path:
        return "", None
    path = Path(transcript_path)
    try:
        size = path.stat().st_size
        offset = state.get("last_transcript_offset") if state.get("last_transcript_path") == str(path) else None
        if isinstance(offset, int) and offset == size:
            return "", size
        if isinstance(offset, int) and 0 <= offset < size:
            start = offset
        elif event_name == "UserPromptSubmit":
            return "", size
        else:
            start = max(size - SCAN_BYTES, 0)
        with path.open("rb") as fh:
            fh.seek(start)
            raw = fh.read().decode("utf-8", errors="ignore")
    except OSError:
        return "", None

    texts: list[str] = []
    for line in raw.splitlines()[-250:]:
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        role = role_from_jsonl(row)
        if role == "user":
            continue
        text = text_from_json(row)
        if text:
            texts.append(text)
    return "\n".join(texts), size


def detect_limit(text: str) -> bool:
    lowered = text.lower()
    return any(re.search(pattern, lowered, re.IGNORECASE | re.DOTALL) for pattern in LIMIT_PATTERNS)


def parse_reset_time(text: str) -> tuple[dt.datetime, bool]:
    local_now = dt.datetime.now().astimezone()
    lowered = text.lower()

    relative = re.search(r"(?:resets?|reset|reinicia|restaura).*?(?:in|em)\s+(\d+)\s*(minutes?|mins?|minutos?|horas?|hours?|hrs?)", lowered)
    if relative:
        amount = int(relative.group(1))
        unit = relative.group(2)
        delta = dt.timedelta(hours=amount) if unit.startswith(("h", "hora")) else dt.timedelta(minutes=amount)
        return (local_now + delta).astimezone(dt.timezone.utc), True

    absolute = re.search(r"(?:resets?|reset|reinicia|restaura).*?(?:(?:at|às|as)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", lowered)
    if absolute:
        hour = int(absolute.group(1))
        minute = int(absolute.group(2) or "0")
        suffix = absolute.group(3)
        if suffix == "pm" and hour < 12:
            hour += 12
        if suffix == "am" and hour == 12:
            hour = 0
        candidate = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if candidate <= local_now:
            candidate += dt.timedelta(days=1)
        return candidate.astimezone(dt.timezone.utc), True

    return now_utc() + dt.timedelta(hours=RESET_FALLBACK_HOURS), False


def maybe_close_old_claude() -> bool:
    if os.environ.get("CLAUDE_LIMIT_PROXY_CLOSE_OLD_CLAUDE", "0") not in {"1", "true", "yes"}:
        return False
    claude_pid = find_ancestor_process("claude")
    return schedule_close_pid(claude_pid)


def maybe_close_recorded_claude(state: dict[str, Any]) -> bool:
    if os.environ.get("CLAUDE_LIMIT_PROXY_CLOSE_OLD_CLAUDE", "0") not in {"1", "true", "yes"}:
        return False
    pid = state.get("claude_pid_to_close_on_restore")
    return schedule_close_pid(pid if isinstance(pid, int) else None)


def schedule_close_pid(claude_pid: int | None) -> bool:
    if not claude_pid:
        return False
    try:
        subprocess.Popen(
            [sys.executable, "-c", f"import os, signal, time; time.sleep(2)\ntry:\n os.killpg(os.getpgid({claude_pid}), signal.SIGTERM)\nexcept Exception:\n os.kill({claude_pid}, signal.SIGTERM)"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except OSError:
        return False


def force_close_external_terminal(state: dict[str, Any]) -> bool:
    pid_file = state.get("external_shell_pid_file")
    if isinstance(pid_file, str):
        try:
            shell_pid = int(Path(pid_file).read_text(encoding="utf-8").strip())
        except (OSError, ValueError):
            shell_pid = None
        if schedule_close_pid(shell_pid):
            return True
    pid = state.get("external_terminal_pid")
    if not isinstance(pid, int):
        return False
    return schedule_close_pid(pid)


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


def backup_settings() -> Path:
    backup = SETTINGS_PATH.with_suffix(".json.limit-proxy-bak")
    if SETTINGS_PATH.exists() and not backup.exists():
        fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(SETTINGS_PATH.read_bytes())
    if backup.exists():
        backup.chmod(0o600)
    return backup


def apply_proxy(input_data: dict[str, Any], text: str, state: dict[str, Any], transcript_path: str | None = None, transcript_offset: int | None = None) -> None:
    token = get_token()
    if not token:
        emit(f"9router: limite de uso detectado, mas nenhum token do 9router foi encontrado. Defina {NINEROUTER_KEY_ENV} ou {TOKEN_ENV}, ou crie ~/.claude/limit-proxy-token (600).")
        return

    settings = load_settings()
    if settings is None:
        return
    env = settings.setdefault("env", {})
    if not isinstance(env, dict):
        emit("9router: settings.env não é um objeto; 9router não aplicado.")
        return

    reset_at, reset_time_detected = parse_reset_time(text)
    restore_at = reset_at + dt.timedelta(minutes=RESTORE_GRACE_MINUTES)
    cwd = hook_string(input_data, "cwd")

    if not state.get("active"):
        backup_settings()
        state = {
            "active": True,
            "activated_at": now_utc().isoformat(),
            "reset_at": reset_at.isoformat(),
            "reset_time_detected": reset_time_detected,
            "restore_at": restore_at.isoformat(),
            "cwd": cwd,
            "previous_env": {key: env.get(key) for key in MANAGED_KEYS if key in env},
            "previous_present": {key: key in env for key in MANAGED_KEYS},
            "previous_has_completed_onboarding_present": "hasCompletedOnboarding" in settings,
            "previous_has_completed_onboarding": settings.get("hasCompletedOnboarding"),
            "terminal_opened_on_activation": False,
            "terminal_opened_on_restore": False,
            "old_claude_close_scheduled": False,
            "restore_worker_started": False,
            "claude_pid_to_close_on_restore": find_ancestor_process("claude"),
        }
    else:
        state.setdefault("reset_at", reset_at.isoformat())
        state.setdefault("reset_time_detected", reset_time_detected)
        state.setdefault("restore_at", restore_at.isoformat())
        if cwd:
            state["cwd"] = cwd
    if transcript_path and transcript_offset is not None:
        state["last_transcript_path"] = transcript_path
        state["last_transcript_offset"] = transcript_offset
    session_id = session_id_from_transcript(transcript_path) or state.get("session_id")
    if session_id:
        state["session_id"] = session_id

    env.update(MANAGED_ENV)
    # Claude Code lê as credenciais do provider no settings.json ao iniciar;
    # o hook remove o token de novo na restauração/remover para minimizar o tempo de exposição.
    env["ANTHROPIC_AUTH_TOKEN"] = token
    env["NINEROUTER_URL"] = ninerouter_base()
    env["NINEROUTER_KEY"] = token
    settings["hasCompletedOnboarding"] = True

    write_json(STATE_PATH, state)
    write_json(SETTINGS_PATH, settings)

    opened = False
    if not state.get("terminal_opened_on_activation"):
        external_pid_file = str(STATE_DIR / "external-shell.pid")
        terminal_pid = open_terminal(cwd, pid_file=external_pid_file, session_id=state.get("session_id"))
        opened = terminal_pid is not None
        state["terminal_opened_on_activation"] = opened
        if terminal_pid is not None:
            state["external_terminal_pid"] = terminal_pid
            state["external_shell_pid_file"] = external_pid_file
    closed = False
    if opened and not state.get("old_claude_close_scheduled"):
        closed = maybe_close_old_claude()
        state["old_claude_close_scheduled"] = closed
    write_json(STATE_PATH, state)
    if not state.get("restore_worker_started"):
        state["restore_worker_started"] = start_restore_worker()
        write_json(STATE_PATH, state)

    extra = " Novo terminal aberto." if opened else " Reinicie o Claude na mesma pasta para carregar o provider 9router."
    if closed:
        extra += " Processo antigo do Claude agendado para fechar."
    emit(f"9router: provider 9router aplicado até {state['restore_at']}.{extra}")


def restore_proxy(input_data: dict[str, Any], state: dict[str, Any]) -> None:
    settings = load_settings()
    if settings is None:
        return
    env = settings.setdefault("env", {})
    if not isinstance(env, dict):
        emit("9router: settings.env não é um objeto; restauração ignorada.")
        return

    previous_env = state.get("previous_env", {}) if isinstance(state.get("previous_env"), dict) else {}
    previous_present = state.get("previous_present", {}) if isinstance(state.get("previous_present"), dict) else {}
    for key in MANAGED_KEYS:
        if previous_present.get(key):
            env[key] = previous_env.get(key)
        else:
            env.pop(key, None)
    if state.get("previous_has_completed_onboarding_present"):
        settings["hasCompletedOnboarding"] = state.get("previous_has_completed_onboarding")
    else:
        settings.pop("hasCompletedOnboarding", None)

    write_json(SETTINGS_PATH, settings)
    state["active"] = False
    state["restored_at"] = now_utc().isoformat()

    opened = False
    closed = False
    if not state.get("terminal_opened_on_restore"):
        state_cwd = state.get("cwd") if isinstance(state.get("cwd"), str) else None
        session_id = session_id_from_transcript(hook_string(input_data, "transcript_path")) or state.get("session_id")
        terminal_pid = open_terminal(hook_string(input_data, "cwd") or state_cwd, normal_provider=True, pid_file=str(STATE_DIR / "normal-shell.pid"), session_id=session_id)
        opened = terminal_pid is not None
        state["terminal_opened_on_restore"] = opened
        if terminal_pid is not None:
            state["normal_terminal_pid"] = terminal_pid
        if opened:
            closed_current = maybe_close_old_claude()
            closed_recorded = maybe_close_recorded_claude(state)
            closed = closed_current or closed_recorded
            state["old_claude_close_scheduled_on_restore"] = closed
    if not state.get("external_terminal_closed_on_restore"):
        closed_external = force_close_external_terminal(state)
        state["external_terminal_closed_on_restore"] = closed_external
        closed = closed or closed_external
    write_json(STATE_PATH, state)

    extra = " Novo terminal aberto com provider normal." if opened else " Reinicie o Claude para carregar o provider normal."
    if closed:
        extra += " Claude externo agendado para fechar."
    emit(f"9router: provider 9router removido.{extra}")


def start_restore_worker() -> bool:
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), BACKGROUND_ARG],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except OSError:
        return False


def restore_waiter() -> None:
    while True:
        with FileLock():
            state = load_state_for_write()
            if state is None:
                return
            if not isinstance(state, dict) or not state.get("active"):
                return
            restore_at = parse_iso(state.get("restore_at"))
            if not restore_at:
                restore_proxy({"cwd": state.get("cwd")}, state)
                return
            remaining = (restore_at - now_utc()).total_seconds()
            if remaining <= 0:
                restore_proxy({"cwd": state.get("cwd")}, state)
                return
        time.sleep(min(max(remaining, 1), 300))


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == BACKGROUND_ARG:
        restore_waiter()
        return

    try:
        input_data = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        input_data = {}
    if not isinstance(input_data, dict):
        input_data = {}

    if maybe_handle_control_command(input_data):
        return

    with FileLock():
        if DISABLED_PATH.exists():
            emit("9router: sistema de troca automática desativado.", suppress=True)
            return

        state = load_state_for_write()
        if state is None:
            return

        restore_at = parse_iso(state.get("restore_at") if isinstance(state, dict) else None)
        if isinstance(state, dict) and state.get("active") and restore_at and now_utc() >= restore_at:
            restore_proxy(input_data, state)
            return

        transcript_path = hook_string(input_data, "transcript_path")
        text, transcript_offset = recent_non_user_transcript_text(transcript_path, state if isinstance(state, dict) else {}, hook_event(input_data))
        if text and detect_limit(text):
            if transcript_path and transcript_offset is not None and isinstance(state, dict):
                state["last_transcript_path"] = transcript_path
                state["last_transcript_offset"] = transcript_offset
            if isinstance(state, dict) and state.get("active"):
                if not state.get("restore_worker_started"):
                    state["restore_worker_started"] = start_restore_worker()
                reset_at, reset_time_detected = parse_reset_time(text)
                new_restore_at = reset_at + dt.timedelta(minutes=RESTORE_GRACE_MINUTES)
                current_restore_at = parse_iso(state.get("restore_at"))
                should_update_reset = reset_time_detected and (
                    not state.get("reset_time_detected")
                    or current_restore_at is None
                    or new_restore_at > current_restore_at
                )
                if should_update_reset:
                    state["reset_at"] = reset_at.isoformat()
                    state["reset_time_detected"] = True
                    state["restore_at"] = new_restore_at.isoformat()
                    write_json(STATE_PATH, state)
                    emit("9router: horário real de reset detectado; restauração atualizada.", suppress=True)
                    return
                write_json(STATE_PATH, state)
                emit("9router: provider 9router já ativo; mantendo o horário de reset original.", suppress=True)
                return
            apply_proxy(input_data, text, state if isinstance(state, dict) else {}, transcript_path, transcript_offset)
            return
        if transcript_path and transcript_offset is not None and isinstance(state, dict):
            state["last_transcript_path"] = transcript_path
            state["last_transcript_offset"] = transcript_offset
            write_json(STATE_PATH, state)

    emit("9router: nenhuma ação de limite necessária.", suppress=True)


if __name__ == "__main__":
    main()