#!/usr/bin/env bash
# Lembrete injetado no início de cada prompt do usuário (Claude Code,
# evento UserPromptSubmit). Equivalente ao gatilho "chat.message" do
# plugin opencode. O texto é impresso no stdout para virar contexto.
set -euo pipefail

if [ "${OPENCODE_SKIP_WORKFLOW:-}" = "1" ]; then
  exit 0
fi

cat <<'EOF'
[Rotina] Antes de iniciar qualquer ação (pesquisa, edição ou implementação), execute a skill entreviste-me para validar o entendimento do pedido.
EOF
