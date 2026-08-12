# Processo de Code Review

## 0. Garantir Context7

Identifique as tecnologias presentes no diff e use o MCP `context7` para documentação atualizada.

Se o MCP `context7` não estiver disponível, instale/configure automaticamente seguindo `references/context7.md` antes de continuar.

## 1. Fixar o ponto de referência

O que o usuário disse é o ponto fixo — um SHA de commit, nome de branch, tag, `main`, `HEAD~5`, etc. Se ele não especificou, pergunte.

Capture o comando de diff uma vez: `git diff <ponto-fixo>...HEAD` (três pontos, para que a comparação seja contra o merge-base). Anote também a lista de commits via `git log <ponto-fixo>..HEAD --oneline`.

Antes de prosseguir, confirme que o ponto fixo resolve (`git rev-parse <ponto-fixo>`) e que o diff não está vazio. Uma referência inválida ou diff vazio deve falhar aqui — não dentro de dois sub-agentes paralelos.

## 2. Identificar a fonte da especificação

Procure a especificação de origem, nesta ordem:

1. Referências a issues nas mensagens de commit (`#123`, `Closes #45`, GitLab `!67`, etc.) — busque via o fluxo em `docs/agents/issue-tracker.md`.
2. Um caminho que o usuário passou como argumento.
3. Um arquivo PRD/spec em `docs/`, `specs/` ou `.scratch/` correspondendo ao nome da branch ou funcionalidade.
4. Se nada for encontrado, pergunte ao usuário onde está a especificação. Se ele disser que não há, o sub-agente de **Especificação** será pulado e reportará "especificação não disponível".

## 3. Identificar as fontes de padrões

Qualquer coisa no repositório que documente como o código deve ser escrito, como `CODING_STANDARDS.md` ou `CONTRIBUTING.md`.

Além do que o repositório documenta, o eixo de Padrões sempre carrega a baseline de code smells em `references/code-smells.md`.

## 4. Lançar ambos os sub-agentes em paralelo

Envie uma única mensagem com duas chamadas da ferramenta `Agent`. Use o subagente `general-purpose` para ambos.

### Prompt do sub-agente de Padrões

Inclua:

- O comando de diff completo e a lista de commits.
- A lista de arquivos-fonte de padrões encontrados no passo 3, mais a baseline de smells de `references/code-smells.md` colada integralmente — o sub-agente não tem outro acesso a ela.
- O briefing: "Reporte — por arquivo/trecho quando relevante — (a) cada lugar onde o diff viola um padrão documentado: cite o padrão (arquivo + a regra); e (b) qualquer smell da baseline que você identificar: nomeie-o e cite o trecho. Distinga violações definitivas de questões de julgamento — violações de padrões documentados podem ser definitivas, mas smells da baseline são sempre questões de julgamento, e um padrão documentado do repositório tem prioridade sobre a baseline. Pule o que o ferramental já fiscaliza. Até 400 palavras."

### Prompt do sub-agente de Especificação

Inclua:

- O comando de diff e a lista de commits.
- O caminho ou conteúdo obtido da especificação.
- O briefing: "Reporte: (a) requisitos que a especificação pediu e estão ausentes ou parciais; (b) comportamento no diff que não foi solicitado (scope creep); (c) requisitos que parecem implementados mas cuja implementação parece incorreta. Cite a linha da especificação para cada achado. Até 400 palavras."

Se a especificação estiver ausente, pule o sub-agente de Especificação e anote isso no relatório final.

## 5. Agregar

Apresente os dois relatórios sob os títulos `## Padrões` e `## Especificação`, na íntegra ou levemente limpos. **Não** mescle ou re-ordene os achados — os dois eixos são deliberadamente separados.

Finalize com um resumo de uma linha: total de achados por eixo e o pior problema dentro de cada eixo, se houver. Não escolha um único vencedor entre os eixos.
