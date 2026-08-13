#!/usr/bin/env bash
# Instalação automática do fluxo de trabalho no OpenCode (escopo global).
#
# - Clona o marketplace em ~/marketplaces/MyMarketPlace (se não existir)
# - Mescla plugin + skills.paths + MCP context7 no ~/.config/opencode/opencode.json
#   preservando qualquer config existente (MCP, agentes etc.)
# - Idempotente: rodar de novo é seguro (não duplica entradas)
# - Tudo em escopo de USUÁRIO (global) — nada por projeto
#
# Uso:
#   bash scripts/install-opencode.sh
set -euo pipefail

REPO_URL="https://github.com/Nomadiction8991/MyMarketPlace.git"
MARKETPLACE_DIR="${MARKETPLACE_DIR:-${HOME}/marketplaces/MyMarketPlace}"
CONFIG_FILE="${CONFIG_FILE:-${HOME}/.config/opencode/opencode.json}"

PLUGIN_PATH="${MARKETPLACE_DIR}/plugins/fluxo-trabalho/index.ts"
SKILLS_PATH="${MARKETPLACE_DIR}/plugins/fluxo-trabalho/skills"

# 1. Clonar o marketplace
if [ -d "${MARKETPLACE_DIR}/.git" ]; then
  echo "Marketplace já existe em ${MARKETPLACE_DIR}"
  echo "Dica: rode 'git -C ${MARKETPLACE_DIR} pull' para atualizar."
else
  echo "Clonando marketplace em ${MARKETPLACE_DIR}..."
  mkdir -p "$(dirname "${MARKETPLACE_DIR}")"
  git clone "${REPO_URL}" "${MARKETPLACE_DIR}"
fi

# 2. Garantir que o diretório de config existe
mkdir -p "$(dirname "${CONFIG_FILE}")"

# 3. Criar config se não existir
if [ ! -f "${CONFIG_FILE}" ]; then
  cat > "${CONFIG_FILE}" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": ["${PLUGIN_PATH}"],
  "skills": {
    "paths": ["${SKILLS_PATH}"]
  },
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}" },
      "enabled": true
    }
  }
}
EOF
  echo "Config criado: ${CONFIG_FILE}"
else
  # Mesclar preservando o resto (MCP, agentes, etc.)
  TMP_FILE="$(mktemp)"
  if ! jq --arg plugin "${PLUGIN_PATH}" --arg skills "${SKILLS_PATH}" '
      .plugin = ((.plugin // []) | if index($plugin) then . else . + [$plugin] end)
      | .skills.paths = ((.skills.paths // []) | if index($skills) then . else . + [$skills] end)
      | .mcp.context7 = {
          "type": "remote",
          "url": "https://mcp.context7.com/mcp",
          "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}" },
          "enabled": true
        }
    ' "${CONFIG_FILE}" > "${TMP_FILE}"; then
    echo "ERRO: falha ao mesclar ${CONFIG_FILE} (jq). Config não alterado." >&2
    rm -f "${TMP_FILE}"
    exit 1
  fi
  mv "${TMP_FILE}" "${CONFIG_FILE}"
  echo "Config atualizado: ${CONFIG_FILE}"
fi

echo
echo "Pronto! Tudo configurado no escopo do USUÁRIO (global):"
echo "- Plugin: ${PLUGIN_PATH}"
echo "- Skills: ${SKILLS_PATH}"
echo "- MCP context7: https://mcp.context7.com/mcp"
echo "Reinicie o OpenCode para carregar."
