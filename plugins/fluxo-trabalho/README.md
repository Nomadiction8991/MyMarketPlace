# Fluxo de Trabalho (plugin do marketplace)

Pacote único do marketplace — funciona em **OpenCode** e **Claude Code**.

Rotina de trabalho que roda ao final de cada resposta da IA quando há
alterações pendentes no git (**passo 1: code-review** — skill
`code-review`). Além disso, **antes de cada resposta** injeta o lembrete
da skill `entreviste-me`. Passos futuros = novas linhas no `run.sh`.

## Estrutura

```
plugins/fluxo-trabalho/
├── .claude-plugin/plugin.json  # manifest nativo do Claude Code
├── hooks/hooks.json            # UserPromptSubmit → entrevista.sh, PostToolUse → mark-edit.sh, Stop → run.sh
├── hooks/entrevista.sh         # lembrete (Claude)
├── hooks/mark-edit.sh          # marca edição de arquivo (PostToolUse Write|Edit)
├── hooks/run.sh                # rotina universal (os dois runtimes)
├── hooks/code-review.sh        # passo 1 (reutilizável isolado)
├── index.ts                    # gatilho do OpenCode (chat.message + session.idle)
└── skills/                     # 7 skills embutidas
```

Os scripts referenciam tudo via `${CLAUDE_PLUGIN_ROOT}` (Claude) ou o
próprio diretório (OpenCode) — nunca paths absolutos.

## Instalação

### Claude Code

```
/plugin marketplace add <git-url-do-marketplace>   # ou ./caminho/local
/plugin install fluxo-trabalho@my-marketplace
```

Escolha o escopo (user/project/local) e `/reload-plugins` se pedir.
Skills ficam namespaced (`fluxo-trabalho:code-review` etc.); hooks
(UserPromptSubmit + Stop) são registrados nativamente.

### OpenCode

No `opencode.json` do projeto de destino:

```json
{
  "plugin": ["<caminho-do-marketplace>/plugins/fluxo-trabalho/index.ts"],
  "skills": {
    "paths": ["<caminho-do-marketplace>/plugins/fluxo-trabalho/skills"]
  }
}
```

## Comportamento

- **Início de resposta**: lembrete entreviste-me (`chat.message` no OpenCode,
  `UserPromptSubmit` no Claude Code).
- **Edição de arquivo**: marca um flag por projeto (`tool.execute.after`
  write/edit/patch no OpenCode, `PostToolUse` `Write|Edit` no Claude Code).
- **Fim de resposta**: rotina (`session.idle` no OpenCode, `Stop` no Claude
  Code → `run.sh`) **só se** houve edição de arquivo nesta sessão (flag) E
  houver alterações pendentes no git (`git status --porcelain`).
- `code-review.sh` detecta a CLI disponível (`OpenCode` ou `claude`), com
  prioridade para o runtime que chamou o hook; se nenhum existir, avisa e
  sai sem erro.
- Anti-recursão: `OPENCODE_SKIP_WORKFLOW=1` / `OPENCODE_SKIP_CODE_REVIEW=1`
  (OpenCode) e `CLAUDE_CODE_DISABLE_HOOKS=1` (Claude) + `flock`.