# Regras Essenciais

- Use `git diff` sem argumentos para modificações não stageadas; se houver stage, inclua `git diff --cached`.
- Se o usuário fornecer commit, branch, tag, `main` ou outro ponto fixo, compare com `git diff <ponto-fixo>...HEAD`.
- Antes da análise, identifique tecnologias no diff e use o MCP context7 para documentação atualizada; se ele não existir, instale/configure automaticamente seguindo `references/context7.md`.
- Inclua a verificação de roda reinventada seguindo `references/roda-reinventada.md`.
- O rastreador de issues deve ter sido fornecido; execute `/setup-matt-pocock-skills` se `docs/agents/issue-tracker.md` estiver faltando.
- Ao instalar automação, siga `references/hooks.md`; a pasta `hooks/` contém os artefatos instaláveis.
- Hooks e MCPs exigidos por esta skill não são opcionais: devem existir e funcionar globalmente. Se faltarem, instale/configure antes de continuar.
- Mesmo sem hook instalado, ao finalizar uma resposta que modificou arquivos ou produziu alteração de código, execute `code-review` automaticamente. Se encontrar problemas acionáveis, corrija-os e execute `code-review` novamente. Repita até não restarem problemas acionáveis ou até completar 5 passagens totais de revisão. Se não houver problemas acionáveis na 1ª, 2ª ou 3ª passagem, pare imediatamente. Se ainda houver problemas depois da 5ª passagem, reporte os achados restantes sem continuar. Se nenhum código foi alterado no turno, não faça nada.
