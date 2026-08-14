# Marketplace

Marketplace de plugins para **OpenCode** e **Claude Code** — os plugins
`fluxo-trabalho` e `ai-memory` funcionam nos dois runtimes.

Este repositório é **somente a criação e estrutura do marketplace** — as
IAs não rodam aqui. O plugin funciona nos dois runtimes quando instalado
em outro projeto.

## Estrutura

```txt
.
  .claude-plugin/marketplace.json  # catálogo nativo do Claude Code
  index.json                       # catálogo (formato aberto)
  plugins/fluxo-trabalho/           # plugin + pacote npm + skills
    .claude-plugin/plugin.json     # manifest do plugin
    hooks/hooks.json               # gatilhos nativos do Claude Code
    hooks/entrevista.sh            # lembrete (UserPromptSubmit)
    hooks/mark-edit.sh             # marca edição (PostToolUse Write|Edit)
    hooks/run.sh                   # rotina (Stop) — passo 1: code-review
    hooks/code-review.sh           # passo de code-review (reutilizável)
    index.ts                       # plugin OpenCode (chat.message + session.idle)
    skills/                          # 7 skills embutidas no plugin
    package.json                    # pacote npm @nomadiction8991/fluxo-trabalho
  plugins/ai-memory/                 # plugin + pacote npm + instalador explícito
    package.json                     # pacote npm @nomadiction8991/ai-memory
```

## Instalação

Guia passo a passo para Claude Code e OpenCode em **[INSTALL.md](INSTALL.md)**.

## Plugins

- `fluxo-trabalho` (`plugins/fluxo-trabalho/`): lembrete entreviste-me no
  início de cada prompt + rotina ao final de cada resposta (passo 1 =
  code-review). Inclui 7 skills: `entreviste-me`, `code-review`, `commit`,
  `chamado-tomticket`, `frontend-design`, `linguagem`, `mr-gitlab`.

- `ai-memory` (`plugins/ai-memory/`): cliente do servidor de memória com MCP,
  hooks e 6 skills. O pacote npm instala o plugin e as skills no OpenCode;
  o comando `npx --yes --package @nomadiction8991/ai-memory@0.4.0 ai-memory-setup` faz a configuração
  explícita do binário, token e integrações.

## Instalação npm no OpenCode

Os pacotes npm desta versão foram preparados e validados localmente, mas ainda
precisam ser publicados no npm. Depois da publicação, use os comandos abaixo.

Na tela **Install plugin** do OpenCode, escolha `global` e informe:

```text
@nomadiction8991/fluxo-trabalho
@nomadiction8991/ai-memory
```

Ou use o CLI:

```bash
opencode plugin --global @nomadiction8991/fluxo-trabalho@0.4.0
opencode plugin --global @nomadiction8991/ai-memory@0.4.0
npx --yes --package @nomadiction8991/ai-memory@0.4.0 ai-memory-setup
```

O primeiro comando de cada pacote entra no `plugin` do OpenCode. Ao iniciar,
os plugins registram suas próprias skills; o `ai-memory` também registra o
MCP sem gravar o token no pacote. Reinicie o OpenCode após instalar.

O Claude Code continua usando o marketplace nativo, porque o npm não instala
hooks `hooks.json` nem manifests `.claude-plugin` nesse runtime.
