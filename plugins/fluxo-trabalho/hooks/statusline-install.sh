#!/usr/bin/env bash
# SessionStart: publica a statusline do fluxo-trabalho no arquivo legado
# ~/.claude/statusline-command.sh, que o wrapper do 9router já chama e
# complementa com sua própria linha. Idempotente — só regrava se o
# conteúdo mudou.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/scripts/statusline.sh"
DEST="$HOME/.claude/statusline-command.sh"

if [ -f "$DEST" ] && cmp -s "$SRC" "$DEST"; then
  exit 0
fi

install -m 0755 "$SRC" "$DEST"
exit 0
