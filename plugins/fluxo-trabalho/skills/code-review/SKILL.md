---
name: code-review
model: sonnet
effort: medium
description: Ative automaticamente após finalizar todas as edições solicitadas pelo usuário, enquanto as alterações ainda estão pendentes (não commitadas). Revisa os arquivos modificados em dois eixos — Padrões (segue as convenções do repositório?) e Especificação (resolve o que foi pedido?). Apresenta os resultados lado a lado. Também pode ser invocada manualmente com um ponto fixo (commit, branch, tag) para revisar alterações desde ele.
---

Revisão em dois eixos das alterações pendentes (não commitadas):

- **Padrões** — o código está em conformidade com os padrões documentados do repositório?
- **Especificação** — o código implementa fielmente o que foi pedido?

Ambos os eixos rodam como sub-agentes paralelos para não poluir o contexto um do outro, e então esta skill agrega os resultados.

## Arquivos de referência

Leia os arquivos conforme a necessidade:

- `references/regras.md` — regras obrigatórias da skill.
- `references/processo.md` — fluxo operacional completo da revisão.
- `references/code-smells.md` — baseline fixa de smells usada pelo eixo de Padrões.
- `references/roda-reinventada.md` — verificação de código manual substituível por recursos nativos do stack.
- `references/dois-eixos.md` — razão para manter Padrões e Especificação separados.
- `references/hooks.md` — hooks desta skill: neste marketplace vêm do plugin `fluxo-trabalho` (Claude: `PostToolUse` Write|Edit → `mark-edit.sh`; `Stop` → `hooks/run.sh` → `hooks/code-review.sh`. opencode: `tool.execute.after` → flag; `session.idle` → `hooks/run.sh`). Não instale hooks globais.
- `references/context7.md` — instalação/configuração obrigatória do MCP context7 global no Claude Code e no opencode.
