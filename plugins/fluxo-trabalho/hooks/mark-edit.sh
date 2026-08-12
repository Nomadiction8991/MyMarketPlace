#!/usr/bin/env bash
# Marca que houve edição de arquivo nesta sessão (Claude Code, evento
# PostToolUse com matcher Write|Edit). O flag é por projeto; o Stop (run.sh)
# só roda o code-review se este flag existir.
set -euo pipefail

DATA_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
PROJECT_KEY="$(printf '%s' "${CLAUDE_PROJECT_DIR:-$(pwd)}" | md5sum | cut -c1-8)"

mkdir -p "${DATA_DIR}"
touch "${DATA_DIR}/fluxo-edited-${PROJECT_KEY}.flag"
