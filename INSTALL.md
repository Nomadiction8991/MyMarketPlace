# Guia de Instalação

Instalação do plugin `fluxo-trabalho` deste marketplace no **Claude Code**
e no **OpenCode**. O plugin traz o fluxo completo: lembrete da skill
`entreviste-me` no início, detecção de edição de arquivos e rotina com
`code-review` ao final de cada resposta, além de 7 skills embutidas.

---

## Claude Code

### 1. Adicionar o marketplace

Dentro do Claude Code, no diretório do projeto onde você quer usar o fluxo:

```
/plugin marketplace add Nomadiction8991/MyMarketPlace
```

- Shorthand GitHub (recomendado — recebe atualizações):
  `/plugin marketplace add Nomadiction8991/MyMarketPlace`
- URL completa, se preferir:
  `/plugin marketplace add https://github.com/Nomadiction8991/MyMarketPlace.git`
- Local (para testar antes de subir):
  `/plugin marketplace add /caminho/para/MyMarketPlace`

### 2. Instalar o plugin

```
/plugin install fluxo-trabalho@my-marketplace
```

O Claude pergunta o **escopo**:

| Escopo | Onde fica | Uso |
|---|---|---|
| `user` | seu usuário, todos os projetos | seu fluxo pessoal |
| `project` | `.claude/settings.json` do repo | time/collabs no mesmo repo |
| `local` | só neste repo (gitignored) | teste pontual |

### 3. Ativar

Se a instalação pedir, rode:

```
/reload-plugins
```

Pronto. A partir daqui, em toda sessão:

- **Início**: lembrete para executar a skill `entreviste-me`
- **Edição**: `Write`/`Edit` marca que houve edição
- **Fim**: se houve edição e há alterações no git, roda o `code-review`

### Verificar / gerenciar

```
/plugin list                 # instalados
/plugin marketplace list     # marketplaces cadastrados
/plugin uninstall fluxo-trabalho@my-marketplace
```

### Atualizar

Quando houver versão nova no marketplace:

```
/plugin marketplace update
```

Versão nova é sinalizada pelo `version` no `plugin.json` do pacote.

---

## OpenCode

### 1. Clonar o marketplace

O OpenCode não tem "marketplace": ele carrega o plugin e as skills por
**caminho no disco**. Então clone o repo uma vez na sua máquina:

```bash
git clone https://github.com/Nomadiction8991/MyMarketPlace.git ~/marketplaces/MyMarketPlace
```

### 2. Apontar no `opencode.json` do projeto

No projeto de destino, edite o `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["~/marketplaces/MyMarketPlace/plugins/fluxo-trabalho/index.ts"],
  "skills": {
    "paths": ["~/marketplaces/MyMarketPlace/plugins/fluxo-trabalho/skills"]
  }
}
```

Use o caminho absoluto (ou `~`) do clone.

### 3. Reiniciar o OpenCode

Feche e abra o OpenCode no projeto. O plugin passa a:

- **Início**: injetar o lembrete da skill `entreviste-me`
- **Edição**: `write`/`edit`/`patch` marca que houve edição
- **Fim** (`session.idle`): se houve edição e há alterações no git, roda o
  `code-review`

### Verificar

- O plugin carregou: um log `[Rotina] ...` no início das respostas
- As skills aparecem na lista de skills disponíveis (`entreviste-me`,
  `code-review`, `commit`, `chamado-tomticket`, `frontend-design`,
  `linguagem`, `mr-gitlab`)

### Atualizar

```bash
cd ~/marketplaces/MyMarketPlace && git pull
```

Skills e plugin atualizam juntos — basta reiniciar o OpenCode.

---

## Requisitos

- **Claude Code**: instalação padrão; suporte a `/plugin` (versão atual).
- **OpenCode**: Node/Bun no ambiente (o plugin é carregado pelo runtime).
- **Git** nos projetos onde o fluxo roda (o code-review verifica
  `git status --porcelain` antes de revisar).
- **OpenCode ou claude** na máquina de destino: o `code-review.sh` detecta
  qual dos dois está disponível para disparar a revisão; se nenhum existir,
  ele avisa e sai sem erro.

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| `[Rotina]` não aparece | plugin não carregou | confira `plugin` no `opencode.json` / escopo no Claude; reinicie |
| code-review não roda no fim | não houve edição detectada, ou nada no git | edite um arquivo e deixe alterações pendentes |
| code-review não roda no Claude | hook `Stop` não registrado | reinstale o plugin e rode `/reload-plugins` |
| skill não aparece | caminho de `skills.paths` errado | aponte para `.../fluxo-trabalho/skills` (pasta que contém as subpastas de skill) |
