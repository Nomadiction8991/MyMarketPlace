---
name: ai-memory-login
description: "Use this skill when the ai-memory client reports a missing or invalid credential (hooks log 'credencial ausente', MCP connection fails with 401, or the user needs to configure the ai-memory token). It walks the agent through asking the user for the token and saving it in the standard secrets file so the plugin/hooks/skills can communicate with the ai-memory server."
---

# ai-memory-login

Quando o cliente ai-memory não tem credencial (hooks avisam "credencial
ausente", MCP falha com 401 ou o usuário diz que a comunicação não
funciona), o AGENTE deve solicitar a credencial ao usuário e configurá-la.

## O que o agente deve fazer

1. **Informe** ao usuário que o ai-memory precisa do **Bearer token** do
   servidor (`https://aimemory.anvy.com.br` por padrão, ou o
   `AI_MEMORY_SERVER_URL` configurado).
2. **Peça** o token. O token é sensível — nunca deixe vazar em logs,
   commits ou arquivos do projeto.
3. **Salve** com a permissão do usuário:

   ```bash
   mkdir -p ~/.local/share/opencode/secrets
   printf '%s' '<TOKEN>' > ~/.local/share/opencode/secrets/aimemory-token
   chmod 600 ~/.local/share/opencode/secrets/aimemory-token
   ```

   - Sem quebra de linha no final.
   - `chmod 600` é obrigatório (arquivo de segredo).
4. **Confirme** com um teste rápido:

   ```bash
   curl -fsS -H "Authorization: Bearer $(cat ~/.local/share/opencode/secrets/aimemory-token)" \
     https://aimemory.anvy.com.br/mcp 2>&1 | head -c 300 || true
   ```

   (A resposta pode ser um JSON de erro MCP — o importante é NÃO ser 401.)
5. **Avise** para reiniciar o Claude Code / OpenCode se o MCP ainda não
   estiver conectado, e rode o `memory_status` para confirmar a conexão.

## Alternativa (instalação completa)

Se o usuário preferir automatizar tudo (binário + token + MCP + plugin +
skills), ofereça o instalador:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Nomadiction8991/MyMarketPlace/main/plugins/ai-memory/scripts/install.sh)
```

## Onde o token é lido (ordem)

1. `AI_MEMORY_TOKEN` (env)
2. `$AI_MEMORY_TOKEN_FILE` (env, padrão
   `~/.local/share/opencode/secrets/aimemory-token`)

O plugin nunca embute a credencial — sempre em runtime, do ambiente ou do
arquivo de secrets.
