#!/usr/bin/env bash
# Instala o cliente ai-memory no escopo do USUÁRIO (global):
#   1. Garante o clone do marketplace (plugin + skills + hooks)
#   2. Baixa o binário `ai-memory` do release oficial (com verificação sha256)
#   3. Garante a credencial (Bearer token) em um arquivo de secrets
#   4. Registra o MCP remoto no Claude Code (`claude mcp add --scope user`)
#      e instala o plugin (skills embutidas; o .mcp.json do plugin usa
#      headersHelper lendo o mesmo secrets file)
#   5. Mescla plugin + skills.paths + MCP remoto no config global do OpenCode
#
# Tudo em um comando: plugin + binário + credencial + MCP + hooks + skills.
# Sem credencial, o próprio plugin/hooks/skills avisam e a skill
# `ai-memory-login` ensina o agente a pedir o token ao usuário.
#
# Uso:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Nomadiction8991/MyMarketPlace/main/plugins/ai-memory/scripts/install.sh)
#   AI_MEMORY_TOKEN=xxx bash plugins/ai-memory/scripts/install.sh   # sem prompt
set -euo pipefail

MARKETPLACE_URL="https://github.com/Nomadiction8991/MyMarketPlace.git"
MARKETPLACE_DIR="${MARKETPLACE_DIR:-${HOME}/marketplaces/MyMarketPlace}"
PLUGIN_DIR="${MARKETPLACE_DIR}/plugins/ai-memory"

VERSION="1.26.0"
BIN_REPO="akitaonrails/ai-memory"
SERVER_URL="${AI_MEMORY_SERVER_URL:-https://aimemory.anvy.com.br}"
BIN_DIR="${HOME}/.local/bin"
SECRETS_DIR="${HOME}/.local/share/opencode/secrets"
TOKEN_FILE="${AI_MEMORY_TOKEN_FILE:-${SECRETS_DIR}/aimemory-token}"
OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.json"

# ---------- 1. Marketplace (plugin + skills + hooks) ----------
if [ -d "${MARKETPLACE_DIR}/.git" ]; then
  echo "Marketplace já existe em ${MARKETPLACE_DIR}"
  echo "Dica: rode 'git -C ${MARKETPLACE_DIR} pull' para atualizar."
else
  echo "Clonando marketplace em ${MARKETPLACE_DIR}..."
  mkdir -p "$(dirname "${MARKETPLACE_DIR}")"
  git clone "${MARKETPLACE_URL}" "${MARKETPLACE_DIR}"
fi
PLUGIN_PATH="${PLUGIN_DIR}/index.ts"
SKILLS_PATH="${PLUGIN_DIR}/skills"

# ---------- 2. Binário ----------
os="$(uname -s)"
arch="$(uname -m)"
case "${os}" in
  Linux)  os_asset="linux" ;;
  Darwin) os_asset="macos" ;;
  *)      echo "ERRO: SO não suportado: ${os}" >&2; exit 1 ;;
esac
case "${arch}" in
  x86_64|amd64)  arch_asset="x86_64" ;;
  aarch64|arm64) arch_asset="aarch64" ;;
  *) echo "ERRO: arquitetura não suportada: ${arch}" >&2; exit 1 ;;
esac

ASSET="ai-memory-${os_asset}-${arch_asset}.tar.gz"
URL="https://github.com/${BIN_REPO}/releases/download/v${VERSION}/${ASSET}"

if command -v ai-memory >/dev/null 2>&1; then
  echo "Usando ai-memory já instalado: $(command -v ai-memory)"
elif [ -x "${BIN_DIR}/ai-memory" ]; then
  echo "Usando ai-memory já instalado: ${BIN_DIR}/ai-memory"
else
  echo "Baixando ${ASSET} (v${VERSION})..."
  mkdir -p "${BIN_DIR}"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT
  curl -fsSL -o "${TMP_DIR}/${ASSET}" "${URL}"
  curl -fsSL -o "${TMP_DIR}/${ASSET}.sha256" "${URL}.sha256"
  (cd "${TMP_DIR}" && sha256sum -c "${ASSET}.sha256")
  tar -xzf "${TMP_DIR}/${ASSET}" -C "${TMP_DIR}"
  BIN_SRC="$(find "${TMP_DIR}" -maxdepth 2 -type f -name ai-memory | head -1)"
  if [ -z "${BIN_SRC}" ]; then
    echo "ERRO: binário não encontrado dentro do tarball" >&2
    exit 1
  fi
  install -m 0755 "${BIN_SRC}" "${BIN_DIR}/ai-memory"
  echo "Binário instalado em ${BIN_DIR}/ai-memory ($("${BIN_DIR}/ai-memory" --version 2>/dev/null || echo ok))"
fi

# ---------- 3. Credencial ----------
TOKEN="${AI_MEMORY_TOKEN:-}"
if [ -z "${TOKEN}" ] && [ -f "${TOKEN_FILE}" ]; then
  TOKEN="$(tr -d '[:space:]' < "${TOKEN_FILE}")"
  echo "Credencial já existente: ${TOKEN_FILE}"
fi
if [ -z "${TOKEN}" ]; then
  read -r -s -p "Bearer token do ai-memory (cole ou deixe vazio para pular): " TOKEN
  echo
fi
if [ -n "${TOKEN}" ]; then
  mkdir -p "${SECRETS_DIR}"
  printf '%s' "${TOKEN}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  echo "Credencial salva em ${TOKEN_FILE}"
fi

# ---------- 4. Claude Code (MCP + plugin) ----------
if command -v claude >/dev/null 2>&1; then
  if [ -n "${TOKEN}" ]; then
    if claude mcp get ai-memory >/dev/null 2>&1; then
      claude mcp remove ai-memory >/dev/null 2>&1 || true
    fi
    claude mcp add --transport http ai-memory "${SERVER_URL}/mcp" \
      --header "Authorization: Bearer ${TOKEN}" --scope user
    echo "MCP ai-memory registrado no Claude Code (escopo user)"
  else
    echo "Aviso: sem token, MCP do Claude Code não registrado."
  fi
  if claude plugin list 2>/dev/null | grep -q "ai-memory@my-marketplace"; then
    echo "Plugin ai-memory já instalado no Claude Code (skills embutidas)."
  else
    claude plugin marketplace update my-marketplace >/dev/null 2>&1 || true
    claude plugin install ai-memory@my-marketplace --scope user || \
      echo "Aviso: instale manualmente com /plugin install ai-memory@my-marketplace"
    echo "Plugin ai-memory instalado no Claude Code (skills embutidas)."
  fi
else
  echo "Aviso: claude não encontrado no PATH; pulei o registro no Claude Code."
fi

# ---------- 5. OpenCode (plugin + skills.paths + MCP) ----------
mkdir -p "$(dirname "${OPENCODE_CONFIG}")"
if [ ! -f "${OPENCODE_CONFIG}" ]; then
  cat > "${OPENCODE_CONFIG}" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": ["${PLUGIN_PATH}"],
  "skills": {
    "paths": ["${SKILLS_PATH}"]
  },
  "mcp": {}
}
EOF
  echo "Config OpenCode criado: ${OPENCODE_CONFIG}"
else
  TMP_FILE="$(mktemp)"
  if ! jq --arg plugin "${PLUGIN_PATH}" --arg skills "${SKILLS_PATH}" --arg url "${SERVER_URL}/mcp" --arg file "${TOKEN_FILE}" '
      .plugin = ((.plugin // []) | if index($plugin) then . else . + [$plugin] end)
      | .skills.paths = ((.skills.paths // []) | if index($skills) then . else . + [$skills] end)
      | .mcp["ai-memory"] = {
          "type": "remote",
          "url": $url,
          "enabled": true,
          "headers": { "Authorization": "Bearer {file:\($file)}" }
        }
    ' "${OPENCODE_CONFIG}" > "${TMP_FILE}"; then
    echo "ERRO: falha ao mesclar ${OPENCODE_CONFIG} (jq). Config não alterado." >&2
    rm -f "${TMP_FILE}"
    exit 1
  fi
  mv "${TMP_FILE}" "${OPENCODE_CONFIG}"
  echo "Config OpenCode atualizado: ${OPENCODE_CONFIG}"
fi

echo
echo "Pronto! ai-memory configurado no escopo do USUÁRIO:"
echo "- Servidor:    ${SERVER_URL}"
echo "- Plugin+skills: ${PLUGIN_DIR} (OpenCode) / ai-memory@my-marketplace (Claude)"
echo "- Binário:     ${BIN_DIR}/ai-memory"
echo "- Credencial:  ${TOKEN_FILE}"
echo
echo "MCP, hooks e skills configurados. Reinicie Claude Code / OpenCode para carregar."
