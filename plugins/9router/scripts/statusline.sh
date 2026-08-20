#!/usr/bin/env bash
# Statusline do plugin 9router (composta): roda a statusline legada do
# usuário e insere o segmento do 9router na 3ª linha dela (após "hooks"),
# no mesmo padrão visual dos demais segmentos. Se a legada não existir ou
# tiver menos de 3 linhas, o segmento vira uma linha extra (fallback seguro).
LEGACY="$HOME/.claude/statusline-command.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

legacy_out=""
if [ -r "$LEGACY" ] && [ -x "$LEGACY" ]; then
  legacy_out=$("$LEGACY")
fi

router_seg=$(python3 "$ROOT/scripts/statusline.py")

if [ -z "$legacy_out" ]; then
  printf '%s' "$router_seg"
  exit 0
fi

awk -v seg="$router_seg" '
  { lines[NR] = $0 }
  END {
    n = NR
    if (n >= 3) {
      lines[3] = lines[3] "  " seg
    } else {
      n += 1
      lines[n] = seg
    }
    for (i = 1; i <= n; i++) {
      printf "%s", lines[i]
      if (i < n) printf "\n"
    }
  }
' <<< "$legacy_out"
