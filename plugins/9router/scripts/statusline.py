#!/usr/bin/env python3
"""Segmento do 9router pra statusline do Claude Code — mesmo padrão visual
(ícone + cor ANSI) dos demais segmentos da 3ª linha (mcp/skills/hooks)."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

HOME = Path.home()
STATE_PATH = HOME / ".claude" / "limit-proxy" / "state.json"
DISABLED_PATH = HOME / ".claude" / "limit-proxy" / "disabled"

RESET = "\033[0m"
DIM = "\033[2m"
GRAY = "\033[90m"
GREEN = "\033[32m"
YELLOW = "\033[33m"

ICON = "\U0001F501"  # 🔁


def local_hhmm(value: str) -> str:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone()
        return parsed.strftime("%H:%M")
    except ValueError:
        return "?"


def main() -> None:
    if DISABLED_PATH.exists():
        print(f"{GRAY}{ICON} 9router{RESET} {DIM}(off){RESET}")
        return
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    if state.get("active") and state.get("restore_at"):
        until = local_hhmm(str(state["restore_at"]))
        print(f"{YELLOW}{ICON} 9router{RESET} {DIM}(ativo até {until}){RESET}")
        return
    print(f"{GREEN}{ICON} 9router{RESET}")


if __name__ == "__main__":
    main()
