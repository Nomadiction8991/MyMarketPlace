# Hooks Automáticos

Neste marketplace, os hooks desta skill **já vêm do plugin** `fluxo-trabalho`:

- **Claude Code**: `plugins/fluxo-trabalho/hooks/hooks.json` — `PostToolUse` (`Write|Edit`) → `mark-edit.sh` marca edição; evento `Stop` → `hooks/run.sh` → `hooks/code-review.sh`.
- **opencode**: `plugins/fluxo-trabalho/index.ts` — `tool.execute.after` (write/edit/patch) marca edição; evento `session.idle` → `hooks/run.sh` → `hooks/code-review.sh`.

**Não instale hooks globais** nesta instalação: os templates de autofix globais (Claude e opencode) são apenas para uso standalone e não acompanham este plugin.
