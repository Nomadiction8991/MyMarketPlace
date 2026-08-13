#!/usr/bin/env bash
# Emite um evento de ciclo de vida para o servidor ai-memory.
# Usado pelos hooks do Claude Code (hooks/hooks.json) e pelo plugin do OpenCode.
#
# Resolução em runtime (nada hardcoded no plugin):
#   - Binário:   $AI_MEMORY_BIN  >  ai-memory no PATH  >  ~/.local/bin/ai-memory
#   - Servidor:  $AI_MEMORY_SERVER_URL (padrão: https://aimemory.anvy.com.br)
#   - Credencial: $AI_MEMORY_TOKEN  >  $AI_MEMORY_TOKEN_FILE (padrão: ~/.local/share/opencode/secrets/aimemory-token)
#
# Uso:
#   emit.sh <event> [<agent>]   (agent padrão: claude-code; OpenCode usa open-code)
set -euo pipefail

EVENT="${1:-}"
AGENT="${2:-claude-code}"
if [ -z "${EVENT}" ]; then
  echo "uso: emit.sh <event> [<agent>]" >&2
  exit 1
fi

# 1. Binário
BIN="${AI_MEMORY_BIN:-}"
if [ -z "${BIN}" ]; then
  BIN="$(command -v ai-memory || true)"
fi
if [ -z "${BIN}" ] && [ -x "${HOME}/.local/bin/ai-memory" ]; then
  BIN="${HOME}/.local/bin/ai-memory"
fi
if [ -z "${BIN}" ]; then
  echo "ai-memory: binário não encontrado. Instale com: bash plugins/ai-memory/scripts/install.sh" >&2
  exit 0
fi

# 2. Servidor
SERVER="${AI_MEMORY_SERVER_URL:-https://aimemory.anvy.com.br}"
SERVER="${SERVER%/}"

# 3. Credencial
TOKEN="${AI_MEMORY_TOKEN:-}"
if [ -z "${TOKEN}" ]; then
  TOKEN_FILE="${AI_MEMORY_TOKEN_FILE:-${HOME}/.local/share/opencode/secrets/aimemory-token}"
  if [ -f "${TOKEN_FILE}" ]; then
    TOKEN="$(tr -d '[:space:]' < "${TOKEN_FILE}")"
  fi
fi
if [ -z "${TOKEN}" ]; then
  echo "ai-memory: credencial ausente. O token não foi encontrado em AI_MEMORY_TOKEN nem em ${AI_MEMORY_TOKEN_FILE:-${HOME}/.local/share/opencode/secrets/aimemory-token}." >&2
  echo "ai-memory: peça o token ao usuário e salve no arquivo acima (chmod 600), ou rode o instalador:" >&2
  echo "ai-memory:   bash <(curl -fsSL https://raw.githubusercontent.com/Nomadiction8991/MyMarketPlace/main/plugins/ai-memory/scripts/install.sh)" >&2
  exit 0
fi

ARGS=(--event "${EVENT}" --agent "${AGENT}" --server-url "${SERVER}")
if [ -n "${TOKEN}" ]; then
  ARGS+=(--auth-token "${TOKEN}")
fi

# Fire-and-forget: hooks nunca devem bloquear o agente.
# timeout 5 sinaliza SIGTERM se o servidor estiver fora.
exec timeout 5 "${BIN}" hook "${ARGS[@]}" < /dev/stdin || exit 0
