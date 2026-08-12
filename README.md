# Marketplace

Marketplace de plugins para **OpenCode** e **Claude Code** — um único
plugin (`fluxo-trabalho`) com skills, hooks e rotina para os dois runtimes.

Este repositório é **somente a criação e estrutura do marketplace** — as
IAs não rodam aqui. O plugin funciona nos dois runtimes quando instalado
em outro projeto.

## Estrutura

```txt
.
  .claude-plugin/marketplace.json  # catálogo nativo do Claude Code
  index.json                       # catálogo (formato aberto)
  plugins/fluxo-trabalho/           # o plugin (único pacote do marketplace)
    .claude-plugin/plugin.json     # manifest do plugin
    hooks/hooks.json               # gatilhos nativos do Claude Code
    hooks/entrevista.sh            # lembrete (UserPromptSubmit)
    hooks/mark-edit.sh             # marca edição (PostToolUse Write|Edit)
    hooks/run.sh                   # rotina (Stop) — passo 1: code-review
    hooks/code-review.sh           # passo de code-review (reutilizável)
    index.ts                       # plugin OpenCode (chat.message + session.idle)
    skills/                        # 7 skills embutidas no plugin
```

## Instalação

Guia passo a passo para Claude Code e OpenCode em **[INSTALL.md](INSTALL.md)**.

## Plugins

- `fluxo-trabalho` (`plugins/fluxo-trabalho/`): lembrete entreviste-me no
  início de cada prompt + rotina ao final de cada resposta (passo 1 =
  code-review). Inclui 7 skills: `entreviste-me`, `code-review`, `commit`,
  `chamado-tomticket`, `frontend-design`, `linguagem`, `mr-gitlab`.