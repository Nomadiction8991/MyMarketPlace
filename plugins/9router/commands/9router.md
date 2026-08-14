---
description: Controla a troca do provider para o 9router (auto-fallback por limite de uso)
argument-hint: "status|on|off|aplicar|remover|token"
---

Este comando é processado diretamente pelo hook `limit-proxy-guard.py` do plugin 9router no evento `UserPromptSubmit`. O mesmo guard roda no `Stop` para detectar mensagens de limite que aparecem depois da resposta do Claude.

Ações:

- `status` — mostra se o 9router está aplicado, o endpoint e o estado da restauração.
- `on` / `off` — ativa ou desativa o sistema de troca automática.
- `aplicar` — aplica o provider 9router manualmente (restauração de segurança em 5h).
- `remover` — remove o 9router e restaura o provider anterior.
- `token` — salva o token em `~/.claude/limit-proxy-token` (permissão 600) a partir de `NINEROUTER_KEY` ou `CLAUDE_LIMIT_PROXY_AUTH_TOKEN`.

Não passe o token no chat. Para configurar token, use `NINEROUTER_KEY`, `CLAUDE_LIMIT_PROXY_AUTH_TOKEN` ou o arquivo `~/.claude/limit-proxy-token` com permissão `600`.

Se esta mensagem aparecer, o hook não interceptou o comando. Peça ao usuário para reiniciar o Claude Code para recarregar os hooks.
