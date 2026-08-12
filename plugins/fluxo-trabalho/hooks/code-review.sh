#!/usr/bin/env bash
set -euo pipefail

if [ "${OPENCODE_SKIP_CODE_REVIEW:-}" = "1" ]; then
  exit 0
fi

if ! git status --porcelain 2>/dev/null | grep -q .; then
  exit 0
fi

PROMPT="Execute a skill code-review para revisar as alterações pendentes (não commitadas) deste repositório."

detect_runner() {
  # 1. Runtime que chamou o hook (mais provável de estar instalado)
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && command -v claude >/dev/null 2>&1; then
    echo "claude"
    return
  fi
  # 2. Qualquer runtime disponível — funciona com um OU outro
  if command -v opencode >/dev/null 2>&1; then
    echo "opencode"
    return
  fi
  if command -v claude >/dev/null 2>&1; then
    echo "claude"
    return
  fi
  echo "none"
}

case "$(detect_runner)" in
  claude)
    export CLAUDE_CODE_DISABLE_HOOKS=1
    RUNNER=("claude" "-p" "$PROMPT")
    ;;
  opencode)
    export OPENCODE_SKIP_CODE_REVIEW=1
    RUNNER=("opencode" "run" "$PROMPT")
    ;;
  none)
    echo "code-review: nenhum runtime encontrado (opencode ou claude) — pulando revisão." >&2
    exit 0
    ;;
esac

(
  flock -n 9 || exit 0
  "${RUNNER[@]}" >/tmp/opencode-code-review.log 2>&1
) 9>/tmp/opencode-code-review.lock
