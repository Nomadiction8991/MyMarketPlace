#!/usr/bin/env bash
set -euo pipefail

if [ "${OPENCODE_SKIP_WORKFLOW:-}" = "1" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve a raiz do plugin: via CLAUDE_PLUGIN_ROOT quando rodando como
# plugin nativo do Claude Code (dir do plugin no cache); senão o pai de
# hooks/ (execução direta via opencode a partir do clone).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
else
  PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

# Só roda a rotina se houve edição de arquivo nesta sessão/projeto
# (flag marcado por mark-edit.sh no Claude ou index.ts no opencode).
DATA_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
PROJECT_KEY="$(printf '%s' "${CLAUDE_PROJECT_DIR:-$(pwd)}" | md5sum | cut -c1-8)"
EDIT_FLAG="${DATA_DIR}/fluxo-edited-${PROJECT_KEY}.flag"

if [ ! -f "${EDIT_FLAG}" ]; then
  exit 0
fi
rm -f "${EDIT_FLAG}"

if ! git status --porcelain 2>/dev/null | grep -q .; then
  exit 0
fi

(
  flock -n 9 || exit 0

  export OPENCODE_SKIP_WORKFLOW=1

  # --- Rotina de trabalho ---
  # Passo 1: code-review das alterações pendentes
  bash "${PLUGIN_ROOT}/hooks/code-review.sh" || true

  # Passos futuros entram aqui, ex.:
  # bash "${PLUGIN_ROOT}/hooks/passo-2-commit.sh" || true
) 9>/tmp/opencode-workflow.lock
