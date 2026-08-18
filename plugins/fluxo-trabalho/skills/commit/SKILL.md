---
name: commit
description: "Cria commits bem formatados seguindo o padrão conventional commit. Use sempre que o usuário falar sobre commit/comitar/dar commit em linguagem natural, mesmo sem chamar a skill diretamente com /commit."
model: haiku
---

# Commit Git Inteligente

Cria commit bem formatado: $ARGUMENTS

## Regra de ouro: contexto isolado

A mensagem do commit é montada **somente** a partir do estado real do repositório — `git status`, `git diff`, `git log` e a leitura dos arquivos alterados. **Nunca** usar histórico da conversa, resumos do chat ou descrições do usuário como fonte da mensagem: se o diff não confirma, não entra no commit.

> Preferência: quando o agente `commit-agent` estiver disponível (Claude: `fluxo-trabalho:commit-agent`; OpenCode: `commit-agent`), delegue a ele a montagem da mensagem — ele inicia com contexto limpo. A confirmação `[S]/[N]` continua sendo feita aqui, no agente principal.

## Estado Atual do Repositório

- Status Git: !`git status --porcelain`
- Branch atual: !`git branch --show-current`
- Alterações em staging: !`git diff --cached --stat`
- Alterações não em staging: !`git diff --stat`
- Commits recentes: !`git log --oneline -5`

## Referências

- **Regras gerais (não negociáveis, inclui limites de tamanho):** `referencias/regras-gerais.md`
- **Fluxo do comando (passo a passo, inclui detecção de projeto Ello):** `referencias/fluxo.md`
- **Especificação Conventional Commits:** `referencias/conventional-commits.md`
- **Variante Ello (projetos do Ello ERP):** `referencias/ello.md` + `templates/ello-commit.md`
- **Template de mensagem:** `templates/commit.md`
- **Ajuda:** `help.md`
