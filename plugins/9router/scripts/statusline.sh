#!/usr/bin/env bash
# Statusline do plugin 9router (componda): preserva a statusline anterior do
# usuário na primeira linha e adiciona o estado do 9router na seguinte.
LEGACY="$HOME/.claude/statusline-command.sh"
if [ -r "$LEGACY" ] && [ -x "$LEGACY" ]; then
  "$LEGACY"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/statusline.py"