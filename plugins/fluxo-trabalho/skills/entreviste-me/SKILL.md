---
name: entreviste-me
model: sonnet
effort: medium
description: Ative automaticamente em quase todo turno de trabalho: qualquer mudança, decisão, plano, implementação, correção, ajuste ou pedido cujo entendimento não esteja 100% claro. Entreviste o usuário para validar o entendimento, questionar suposições e expor riscos antes de agir. Se estiver em dúvida se deve ativar, ative. Não ative apenas para perguntas puramente factuais, saudações ou tarefas triviais sem decisão envolvida.
---

Entreviste-me implacavelmente sobre cada aspecto disso até chegarmos a um entendimento compartilhado. Modele o problema como uma **árvore de decisão**: cada decisão gera os ramos e dependências que dela decorrem.

Conduza a entrevista em **rodadas**. A **fronteira** é o conjunto de decisões cujos pré-requisitos já foram resolvidos — as perguntas que podem ser feitas agora sem presumir respostas ainda não dadas. Faça todas as perguntas da fronteira que sejam independentes entre si na mesma rodada, numerando-as e fornecendo uma resposta recomendada para cada uma. Aguarde minhas respostas antes de avançar para a próxima rodada.

Faça as perguntas da rodada **com a ferramenta nativa de perguntas do runtime**, nunca como texto corrido:

- **opencode**: use a ferramenta `question` — passe todas as perguntas independentes da rodada em um único call (campo `questions`); cada pergunta com `header` curto (até 30 caracteres), `question` completa e `options` (2 a 4) com `label` + `description`. Marque a opção recomendada com "(Recomendada)" no fim do label e coloque-a em primeiro; a resposta customizada (usuário digitar a própria) já vem inclusa automaticamente.
- **Claude Code**: use a ferramenta `AskUserQuestion` — mesmas regras (1 a 4 perguntas por call; 2 a 4 opções por pergunta). Não está disponível em subagents: se estiver em um, faça as perguntas a partir da thread principal.

Se nenhuma das duas estiver disponível (ex.: execução não interativa), pergunte em texto com o mesmo formato das ferramentas — 2 a 4 opções numeradas, descrição curta do que cada uma implica, recomendada marcada e resposta própria permitida:

**P1 — <título da pergunta>**: <pergunta, incluindo contexto>

1. **<opção A>** — <implicação/descrição curta>
2. **<opção B>** — <implicação/descrição curta>
3. **<opção C>** — <implicação/descrição curta>

**Recomendada: 1**

Responda com o número da opção escolhida ou escreva a sua própria resposta.

Cada resposta deve remodelar a árvore: recalcule a fronteira e desbloqueie as decisões que dependem do que foi resolvido. Se uma pergunta depender de outra ainda aberta na rodada atual, deixe-a para uma rodada posterior.

Se um *fato* puder ser descoberto explorando o ambiente (arquivos, ferramentas, código), descubra você mesmo — não me pergunte. Quando uma pergunta da fronteira exigir essa descoberta, use as ferramentas ou um subagente e trate a investigação como pré-requisito pendente; faça imediatamente as demais perguntas independentes. As *decisões*, porém, são minhas — coloque cada uma para mim e aguarde.

## Linguagem

A skill `linguagem` está no mesmo plugin (`fluxo-trabalho`) — sempre disponível, não precisa checar "se existe". Acione-a por nome com `modo=simples-com-termos` para formatar todas as mensagens desta entrevista:

- **opencode**: chame a skill `linguagem` (nome plano, via ferramenta de skill do runtime).
- **Claude Code** (instalado via plugin do marketplace): o namespace é `fluxo-trabalho:linguagem` — invoque por esse nome, não por `/linguagem`.

Se não conseguir acioná-la, siga o estilo padrão da resposta.

## Finalização

A sessão termina quando a fronteira estiver vazia: todos os ramos relevantes foram percorridos e nada ficou silenciosamente presumido. Sumarize as decisões principais e o encaminhamento acordado, peça minha confirmação de que chegamos a um entendimento compartilhado, aguarde minha resposta e só então prossiga com a ação solicitada.
