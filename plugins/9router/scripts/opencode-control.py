#!/usr/bin/env python3
"""Controle do provider 9router para o OpenCode.

Aplica/remove o provider anthropic apontando para o 9router no
opencode.json global (~/.config/opencode/opencode.json), com backup do
arquivo original e estado de restauração em ~/.config/opencode/9router-state.json.

O apiKey é gravado como template {env:NINEROUTER_KEY} — o plugin index.ts do
OpenCode injeta essa variável no processo a partir do arquivo de secrets
(ou o usuário pode exportá-la).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

_HOOKS_DIR = Path(__file__).resolve().parent.parent / "hooks"
sys.path.insert(0, str(_HOOKS_DIR))
from limit_proxy_common import MANAGED_KEYS, get_token, ninerouter_base  # type: ignore  # noqa: E402


def default_config_path() -> Path:
    base = os.environ.get("OPENCODE_CONFIG_DIR", "").strip()
    return (Path(base) if base else Path.home() / ".config" / "opencode") / "opencode.json"


CONFIG_PATH = default_config_path()
BACKUP_PATH = CONFIG_PATH.with_suffix(CONFIG_PATH.suffix + ".9router-bak")
STATE_DIR = Path.home() / ".config" / "opencode"
STATE_PATH = STATE_DIR / "9router-state.json"

PROVIDER_KEY = "anthropic"
OPTIONS_KEY = "options"


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path.with_suffix(path.suffix + ".tmp"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    tmp = Path(path.with_suffix(path.suffix + ".tmp"))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    tmp.replace(path)
    path.chmod(0o600)


def backup_config() -> None:
    if CONFIG_PATH.exists() and not BACKUP_PATH.exists():
        fd = os.open(BACKUP_PATH, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(CONFIG_PATH.read_bytes())
    if BACKUP_PATH.exists():
        BACKUP_PATH.chmod(0o600)


def status() -> None:
    config = load_json(CONFIG_PATH, {}) if CONFIG_PATH.exists() else {}
    state = load_json(STATE_PATH, {})
    provider = config.get("provider", {}) if isinstance(config.get("provider"), dict) else {}
    anthropic = provider.get(PROVIDER_KEY, {}) if isinstance(provider, dict) else {}
    options = anthropic.get(OPTIONS_KEY, {}) if isinstance(anthropic, dict) else {}
    applied = str(options.get("baseURL", "")).startswith(f"{ninerouter_base()}/")
    print("Status do 9router (OpenCode):")
    print(f"- Config: {CONFIG_PATH}")
    print(f"- 9router aplicado: {'sim' if applied else 'não'}")
    print(f"- Endpoint: {ninerouter_base()}")
    print(f"- Token salvo: {'sim' if get_token() else 'não'}")
    if state.get("active"):
        print(f"- Restauração registrada: {state.get('restore_at')}")


def apply_proxy() -> bool:
    token = get_token()
    if not token:
        print("Token não encontrado. Defina NINEROUTER_KEY (ou CLAUDE_LIMIT_PROXY_AUTH_TOKEN) no ambiente, ou crie ~/.local/share/opencode/secrets/9router-token com permissão 600.")
        return False
    if not CONFIG_PATH.exists():
        print(f"{CONFIG_PATH} não existe; nada a aplicar.")
        return False

    config = load_json(CONFIG_PATH, {})
    if not isinstance(config, dict):
        print(f"{CONFIG_PATH} não contém um objeto JSON; operação cancelada.")
        return False
    provider = config.setdefault("provider", {})
    if not isinstance(provider, dict):
        print("provider não é um objeto; operação cancelada.")
        return False

    state = load_json(STATE_PATH, {})
    if not isinstance(state, dict):
        state = {}
    now = dt.datetime.now(dt.timezone.utc)
    if not state.get("active"):
        backup_config()
        anthropic = provider.get(PROVIDER_KEY, {})
        previous = {}
        if isinstance(anthropic, dict):
            previous = {key: value for key, value in anthropic.items()}
        state = {
            "active": True,
            "applied_at": now.isoformat(),
            "previous_provider": previous,
            "previous_provider_present": PROVIDER_KEY in provider,
            "restore_at": (now + dt.timedelta(hours=5)).isoformat(),
        }
    else:
        state.setdefault("restore_at", (now + dt.timedelta(hours=5)).isoformat())

    provider[PROVIDER_KEY] = {
        OPTIONS_KEY: {
            "baseURL": f"{ninerouter_base()}/v1",
            "apiKey": "{env:NINEROUTER_KEY}",
        }
    }
    write_json(STATE_PATH, state)
    write_json(CONFIG_PATH, config)
    print(f"9router aplicado no OpenCode (provider anthropic → {ninerouter_base()}/v1). Reinicie o OpenCode para carregar. Restauração de segurança: {state['restore_at']}.")
    return True


def restore_proxy() -> bool:
    if not CONFIG_PATH.exists():
        print(f"{CONFIG_PATH} não existe; nada a restaurar.")
        return False
    config = load_json(CONFIG_PATH, {})
    if not isinstance(config, dict):
        print(f"{CONFIG_PATH} não contém um objeto JSON; operação cancelada.")
        return False
    state = load_json(STATE_PATH, {})
    if not isinstance(state, dict):
        state = {}
    provider = config.setdefault("provider", {})
    if not isinstance(provider, dict):
        print("provider não é um objeto; operação cancelada.")
        return False

    if state.get("previous_provider_present"):
        provider[PROVIDER_KEY] = state.get("previous_provider", {})
    else:
        provider.pop(PROVIDER_KEY, None)
    state["active"] = False
    state["restored_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    write_json(STATE_PATH, state)
    write_json(CONFIG_PATH, config)
    print("9router removido do OpenCode. Reinicie o OpenCode para carregar o provider original.")
    return True


def save_token_from_env() -> None:
    token = os.environ.get("NINEROUTER_KEY", "").strip() or os.environ.get("CLAUDE_LIMIT_PROXY_AUTH_TOKEN", "").strip()
    if not token:
        print("Defina NINEROUTER_KEY no ambiente; o token será salvo em ~/.local/share/opencode/secrets/9router-token com permissão 600.")
        return
    path = Path.home() / ".local" / "share" / "opencode" / "secrets" / "9router-token"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(token)
    tmp.replace(path)
    path.chmod(0o600)
    print(f"Token salvo em {path}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Controle do provider 9router no OpenCode.")
    parser.add_argument("action", choices=["status", "aplicar", "remover", "token"], nargs="?", default="status")
    parser.add_argument("--config", default=str(CONFIG_PATH), help="Caminho do opencode.json (default: global)")
    args = parser.parse_args()

    if args.config != str(CONFIG_PATH):
        cfg = Path(args.config)
        globals()["CONFIG_PATH"] = cfg
        globals()["BACKUP_PATH"] = cfg.with_suffix(cfg.suffix + ".9router-bak")

    if args.action == "status":
        status()
    elif args.action == "aplicar":
        apply_proxy()
    elif args.action == "remover":
        restore_proxy()
    elif args.action == "token":
        save_token_from_env()
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
