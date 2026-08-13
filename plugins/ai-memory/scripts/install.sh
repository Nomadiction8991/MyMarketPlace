#!/usr/bin/env bash
# Instala o cliente ai-memory no escopo do USUÁRIO (global):
#   1. Baixa o binário `ai-memory` do release oficial (com verificação sha256)
#   2. Garante a credencial (Bearer token) em um arquivo de secrets
#   3. Registra o MCP remoto no Claude Code (`claude mcp add --scope user`)
#   4. Mescla o MCP remoto no config global do OpenCode
#   5. Instala as skills do ai-memory (global, Claude Code + .agents)
#
# Tudo em um comando: binário + credencial + MCP + hooks + skills.
#
# Uso:
#   bash plugins/ai-memory/scripts/install.sh
#   AI_MEMORY_TOKEN=xxx bash plugins/ai-memory/scripts/install.sh   # sem prompt
set -euo pipefail

VERSION="1.26.0"
REPO="akitaonrails/ai-memory"
SERVER_URL="${AI_MEMORY_SERVER_URL:-https://aimemory.anvy.com.br}"
BIN_DIR="${HOME}/.local/bin"
SECRETS_DIR="${HOME}/.local/share/opencode/secrets"
TOKEN_FILE="${AI_MEMORY_TOKEN_FILE:-${SECRETS_DIR}/aimemory-token}"
OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.json"

# ---------- 1. Binário ----------
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
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"

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
  echo "Binário instalado em ${BIN_DIR}/ai-memory ($(ai-memory --version 2>/dev/null || echo ok))"
fi

# ---------- 2. Credencial ----------
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

# ---------- 3. Claude Code ----------
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
else
  echo "Aviso: claude não encontrado no PATH; pulei o registro no Claude Code."
fi

# ---------- 4. OpenCode ----------
if command -v opencode >/dev/null 2>&1 || [ -f "${OPENCODE_CONFIG}" ]; then
  mkdir -p "$(dirname "${OPENCODE_CONFIG}")"
  if [ ! -f "${OPENCODE_CONFIG}" ]; then
    echo '{ "$schema": "https://opencode.ai/config.json", "mcp": {} }' > "${OPENCODE_CONFIG}"
  fi
  TMP_FILE="$(mktemp)"
  if ! jq --arg url "${SERVER_URL}/mcp" --arg file "${TOKEN_FILE}" '
      .mcp["ai-memory"] = {
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
  echo "MCP ai-memory registrado no OpenCode global (${OPENCODE_CONFIG})"
else
  echo "Aviso: opencode não encontrado; pulei o registro no OpenCode."
fi

# ---------- 5. Skills (globais, ambos runtimes) ----------
if command -v ai-memory >/dev/null 2>&1 || [ -x "${BIN_DIR}/ai-memory" ]; then
  echo "Instalando skills do ai-memory (global, Claude Code + .agents)..."
  ai-memory install-skills --scope global --agent both 2>&1 | grep -v "^\[" | tail -12
  echo "Skills instaladas: ~/.claude/skills e ~/.agents/skills (ai-memory-*)"
else
  echo "Aviso: binário ai-memory não disponível; skills não instaladas."
fi

echo
echo "Pronto! Cliente ai-memory configurado no escopo do USUÁRIO:"
echo "- Servidor: ${SERVER_URL}"
echo "- Binário:  ${BIN_DIR}/ai-memory"
echo "- Credencial: ${TOKEN_FILE}"
echo
echo "MCP, hooks e skills configurados. Reinicie Claude Code / OpenCode para carregar."
