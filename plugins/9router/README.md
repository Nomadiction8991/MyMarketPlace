# 9router

Plugin que troca **automaticamente** o provider do Claude Code para o **9router** (`https://9router.anvy.com.br`) quando o uso bate o limite, e restaura o provider original depois do reset. Embute as **9 skills oficiais** do 9router (chat, image, video, tts, stt, embeddings, web-search, web-fetch).

Funciona nos dois runtimes:

| Item | OpenCode | Claude Code |
|------|----------|-------------|
| Plugin | `opencode plugin --global @nomadiction8991/9router` (ou path do `index.ts`) | `/plugin install 9router@my-marketplace` |
| Comando | `/9router` no chat (`chat.message`) | `/9router` (`UserPromptSubmit` → guard) + `commands/9router.md` |
| Automático | detecta rate-limit nas mensagens do chat e aplica | `UserPromptSubmit`/`Stop` varrem o transcript e aplicam |
| Restauração | template `{env:NINEROUTER_KEY}` + estado em `opencode.json` | worker `--restore-wait` restaura após o reset |
| Skills | `skills.paths` registrado pelo `index.ts` | auto-discovery (namespace `9router:`) |

## Como funciona

- **Detecção**: mensagens de limite no transcript (Claude) / nas mensagens do chat (OpenCode).
- **Aplicação**: define `ANTHROPIC_*` apontando para o 9router (Claude: `settings.json` global com backup; OpenCode: provider `anthropic.options` no `opencode.json` global com backup).
- **Restauração**: no horário de reset detectado + 15 min de graça (Claude), ou 5h de segurança (manual).
- **Continuidade**: o novo terminal (ativação e restauração) abre com `claude --resume <id da sessão atual>` — a conversa continua de onde parou, sem perder contexto.
- **Comando manual**: `/9router status|on|off|aplicar|remover|token`.

## Comando manual

`/9router status|on|off|aplicar|remover|token`.

## Statusline (Claude Code)

O hook `SessionStart` registra a statusline do rodapé apontando para `scripts/statusline.sh`, que **compõe** com a statusline anterior do usuário: preserva a primeira linha e adiciona o estado do 9router (`[9router: ativo até HH:MM]` / `[9router: off]` / `[9router: normal]`). Como o Claude copia o plugin para cache, o caminho real é descoberto e regravado a cada sessão (idempotente).

## Token

Resolução em runtime (nada hardcoded): env `NINEROUTER_KEY` → env `CLAUDE_LIMIT_PROXY_AUTH_TOKEN` → arquivo de secrets com permissão 600.

- Claude: `~/.claude/limit-proxy-token` (compatível com a instalação anterior).
- OpenCode: `~/.local/share/opencode/secrets/9router-token`.

Salve com `/9router token` (define a env antes) ou crie o arquivo manualmente.

## Endpoint

Configurável via env `NINEROUTER_URL` (default `https://9router.anvy.com.br`). O plugin usa `<NINEROUTER_URL>/v1` como `ANTHROPIC_BASE_URL`; as skills usam `<NINEROUTER_URL>/v1/...` diretamente.

## Skills embutidas

`skills/` — as 9 skills oficiais do repo [decolua/9router](https://github.com/decolua/9router): `9router` (entry/setup), `9router-chat`, `9router-image`, `9router-video`, `9router-tts`, `9router-stt`, `9router-embeddings`, `9router-web-search`, `9router-web-fetch`.