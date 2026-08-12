---
name: commit
description: "Cria commits bem formatados seguindo o padrão conventional commit. Use sempre que o usuário falar sobre commit/comitar/dar commit em linguagem natural, mesmo sem chamar a skill diretamente com /commit."
model: haiku
---

# Commit Git Inteligente

Cria commit bem formatado: $ARGUMENTS

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
