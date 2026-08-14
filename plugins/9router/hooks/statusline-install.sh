#!/usr/bin/env bash
# SessionStart: registra a statusline do 9router no settings.json do usuário.
# O Claude COPIA o plugin para cache, então o caminho real é descoberto em
# runtime e regravado a cada sessão (idempotente — nada muda se já apontar).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATUS="${ROOT}/scripts/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

python3 - "$STATUS" "$SETTINGS" <<'PY'
import json
import os
import sys

status, settings_path = sys.argv[1], sys.argv[2]
with open(settings_path, encoding="utf-8") as f:
    data = json.load(f)

sl = data.get("statusLine") or {}
if sl.get("type") == "command" and sl.get("command") == status:
    sys.exit(0)

data["statusLine"] = {"type": "command", "command": status}
tmp = settings_path + ".9router-tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, settings_path)
os.chmod(settings_path, 0o600)
PY
exit 0