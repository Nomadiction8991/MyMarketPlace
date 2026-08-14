#!/usr/bin/env python3
"""Estado do 9router para a statusline do Claude Code (leve, sem dependências)."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

HOME = Path.home()
STATE_PATH = HOME / ".claude" / "limit-proxy" / "state.json"
DISABLED_PATH = HOME / ".claude" / "limit-proxy" / "disabled"


def local_hhmm(value: str) -> str:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone()
        return parsed.strftime("%H:%M")
    except ValueError:
        return "?"


def main() -> None:
    if DISABLED_PATH.exists():
        print("[9router: off]")
        return
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    if state.get("active") and state.get("restore_at"):
        print(f"[9router: ativo até {local_hhmm(str(state['restore_at']))}]")
        return
    print("[9router: normal]")


if __name__ == "__main__":
    main()