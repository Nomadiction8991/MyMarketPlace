# Formato de Saída do Code Review

Todo relatório desta skill segue este formato: seções fixas por eixo, achados em blocos numerados, cada bloco com local, nível de severidade e as três camadas de explicação (simples, técnica, recomendação). Não mescle e não re-ordene achados entre eixos.

## Níveis de severidade

| Nível | Marcação | Quando usar |
|-------|----------|-------------|
| Crítico | 🔴 | Quebra ou bloqueia: build, teste, deploy ou funcionalidade principal. |
| Alto | 🟠 | Comportamento errado: o código roda, mas faz o que não deveria. |
| Médio | 🟡 | Risco ou qualidade: pode virar bug, deixa dívida, falta tratamento de caso. |
| Baixo | ⚪ | Estilo e cosmético: indentação, nomenclatura, organização. |

## Estrutura do relatório

Comece com a legenda dos níveis. Depois, as seções nesta ordem:

1. `## Padrões` — achados do eixo de Padrões.
2. `## Especificação` — achados do eixo de Especificação.
3. `## Correções que reportei mal antes` — opcional; só quando esta revisão corrige afirmações imprecisas feitas em relatórios anteriores.
4. `## Resumo` — uma linha: total de achados por eixo e o pior nível de cada eixo, se houver. Não repita recomendações aqui e não escolha um único vencedor entre os eixos.

## Bloco de achado

Cada achado segue exatamente esta ordem:

### <número>. <Título curto> — <marcação> <Nível>

**Local:** arquivo:linha (obrigatório, em destaque no topo do bloco)

**Linguagem simples:**

Explicação em palavras comuns e frases diretas, para leitor não técnico.

**Linguagem técnica:**

O mesmo achado com a terminologia correta do domínio, nomes exatos, comandos e identificadores.

**Recomendação:**

Ação concreta e verificável para corrigir (ex.: "Reverter tests/DuskTestCase.php para o conteúdo de origin/main").
