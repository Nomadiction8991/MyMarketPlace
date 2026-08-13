# AGENTS.md

## O que é este projeto

**Marketplace** de plugins que funcionam tanto para o **Claude (Claude Code)** quanto para o **OpenCode**.

Este repositório é **somente a criação e estrutura do marketplace** — as IAs NÃO rodam aqui. Não há config ativa (`opencode.json`, `.claude/`, `.OpenCode/`) neste repo: tudo aqui é o pacote pronto para instalar em outro projeto.

```txt
.
  .claude-plugin/marketplace.json  # catálogo nativo do Claude Code (marketplace)
  index.json                       # catálogo aberto (id, type, name, version, path, entry)
  plugins/fluxo-trabalho/           # plugin de fluxo de trabalho
    .claude-plugin/plugin.json     # manifest do plugin (nome = namespace)
    hooks/hooks.json               # gatilhos nativos do Claude Code
    hooks/entrevista.sh            # lembrete (UserPromptSubmit)
    hooks/mark-edit.sh             # marca edição (PostToolUse Write|Edit)
    hooks/run.sh                   # rotina (Stop) — passo 1: code-review
    hooks/code-review.sh           # passo de code-review (reutilizável)
    index.ts                       # plugin OpenCode (chat.message + session.idle)
    skills/                        # 7 skills embutidas no plugin
  plugins/ai-memory/                # plugin cliente do servidor ai-memory
    .claude-plugin/plugin.json     # manifest do plugin
    hooks/hooks.json               # gatilhos nativos (SessionStart..SessionEnd)
    hooks/emit.sh                  # emite evento (resolução binário+token em runtime)
    index.ts                       # plugin OpenCode (porta do ai-memory.ts gerado)
    skills/                        # 5 skills embutidas no plugin (vendidas no pacote)
    scripts/install.sh             # clone + binário + credencial + MCP + plugin/skills nos 2 runtimes
```

## Regra de ouro

O pacote deste marketplace **deve funcionar para o Claude E para o OpenCode quando instalado**. Não existe pacote "de um lado só".

| Item | OpenCode (instalação) | Claude Code (instalação) |
|------|----------|-------------|
| Plugin inteiro | `opencode.json` → `plugin` → `<repo>/plugins/fluxo-trabalho/index.ts` | `/plugin install fluxo-trabalho@my-marketplace` (escopo user/project/local) |
| Skills (vendidas em `skills/`) | `opencode.json` → `skills.paths` → `<repo>/plugins/fluxo-trabalho/skills` | embutidas no plugin (auto-discovery, namespace `fluxo-trabalho:`) |
| Hooks | `index.ts`: `chat.message` (lembrete) + `session.idle` (rotina) | `hooks/hooks.json` com `${CLAUDE_PLUGIN_ROOT}` (UserPromptSubmit + Stop) |

## Como funciona o fluxo

- **Início de resposta**: lembrete para a skill `entreviste-me` (Claude: `UserPromptSubmit` → `entrevista.sh`; OpenCode: `chat.message` no `index.ts`).
- **Edição de arquivo**: marca um flag por projeto (Claude: `PostToolUse` `Write|Edit` → `mark-edit.sh`; OpenCode: `tool.execute.after` write/edit/patch no `index.ts`).
- **Fim de resposta**: rotina `run.sh` só se houve edição de arquivo nesta sessão (flag) E há alterações pendentes no git (Claude: `Stop`; OpenCode: `session.idle`). Passo 1: `code-review.sh` (detecta o runtime disponível; anti-recursão via `OPENCODE_SKIP_WORKFLOW`/`OPENCODE_SKIP_CODE_REVIEW`/`CLAUDE_CODE_DISABLE_HOOKS` + flock). Novos passos = novas linhas no `run.sh`.

## Regras

- NUNCA adicionar `opencode.json`, `.claude/` ou `.OpenCode/` neste repositório — este repo não roda IAs. Exceção: `.claude-plugin/` na raiz é o manifest do marketplace (não é config ativa) — manter sempre.
- Hooks nativos do Claude Code ficam em `plugins/fluxo-trabalho/hooks/hooks.json`, usando `${CLAUDE_PLUGIN_ROOT}` em todo caminho (nunca paths absolutos nem relativos ao cwd). Lembrete: o Claude COPIA o plugin para cache na instalação — nada de referências fora do diretório do plugin.
- Skills ficam em `plugins/fluxo-trabalho/skills/<nome>/`. Ao criar/atualizar skill: edite a pasta no plugin, revise o SKILL.md e suba a versão do plugin.
- `index.json` é o catálogo — mantê-lo em dia (id, type, name, version, description, path, entry, tags).
- Bump de versão em TODO release: `.claude-plugin/marketplace.json` e `plugins/fluxo-trabalho/.claude-plugin/plugin.json` — é o sinal de atualização para o Claude.

## Pacotes ativos (referência)

- `fluxo-trabalho` (`plugins/fluxo-trabalho/`): pacote único instalável em OpenCode E Claude Code. `index.ts` (gatilho OpenCode: `chat.message` injeta lembrete da skill entreviste-me, `tool.execute.after` marca edição e `session.idle` chama `run.sh`), `hooks/` com `entrevista.sh` + `mark-edit.sh` + `run.sh` + `code-review.sh` (rotina universal em bash — passo 1: code-review; roda só se houve edição de arquivo na sessão). No Claude, os gatilhos são nativos: `hooks/hooks.json` (UserPromptSubmit → entrevista.sh, PostToolUse Write|Edit → mark-edit.sh, Stop → run.sh) via `.claude-plugin/plugin.json`. Incremental — novos passos são linhas no `run.sh`.
- `ai-memory` (`plugins/ai-memory/`): cliente do servidor ai-memory (MCP remoto `https://aimemory.anvy.com.br` + hooks de ciclo de vida). OpenCode: `index.ts` (porta do `ai-memory.ts` gerado por `install-hooks`, lendo servidor/token de env > secrets). Claude: `hooks/hooks.json` (SessionStart, UserPromptSubmit, Pre/PostToolUse, PreCompact, Stop, SessionEnd) → `hooks/emit.sh` — resolução de binário/token em runtime, nada hardcoded. Skills embutidas em `skills/` (5 gerenciadas: retrieval, handoff, durable-pages, learning-maintenance, routing-install) — vendidas no pacote, auto-discovery no Claude, `skills.paths` no OpenCode. `scripts/install.sh` garante o clone do marketplace, baixa o binário do release oficial (sha256), pergunta o token e registra MCP + plugin + skills nos dois runtimes (escopo usuário). Credencial padrão: `~/.local/share/opencode/secrets/aimemory-token`.
- Skills embutidas (no fluxo-trabalho): `entreviste-me`, `code-review` (1º passo da rotina; também invocada isolada), `commit`, `chamado-tomticket`, `frontend-design`, `linguagem`, `mr-gitlab`.