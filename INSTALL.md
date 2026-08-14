# Guia de Instalação

Instalação do plugin `fluxo-trabalho` deste marketplace no **Claude Code**
e no **OpenCode**. O plugin traz o fluxo completo: lembrete da skill
`entreviste-me` no início, detecção de edição de arquivos e rotina com
`code-review` ao final de cada resposta, além de 7 skills embutidas.

> **Política de escopo: sempre usuário.** O plugin, as skills e os MCPs
> (context7) são instalados **no escopo do usuário (global)** — valem para
> todos os seus projetos, em qualquer máquina sua. Nada é configurado por
> projeto. Escopo por projeto só deve ser usado quando você quiser
> deliberadamente algo diferente do padrão.

---

## Claude Code

### 1. Adicionar o marketplace

Dentro do Claude Code:

```
/plugin marketplace add Nomadiction8991/MyMarketPlace
```

- Shorthand GitHub (recomendado — recebe atualizações):
  `/plugin marketplace add Nomadiction8991/MyMarketPlace`
- URL completa, se preferir:
  `/plugin marketplace add https://github.com/Nomadiction8991/MyMarketPlace.git`
- Local (para testar antes de subir):
  `/plugin marketplace add /caminho/para/MyMarketPlace`

### 2. Instalar o plugin (escopo usuário)

```
/plugin install fluxo-trabalho@my-marketplace
```

Escolha o escopo **`user`** (ou use o CLI sem interação):

```bash
claude plugin install fluxo-trabalho@my-marketplace --scope user
```

| Escopo | Onde fica | Uso |
|---|---|---|
| `user` ✅ (padrão) | seu usuário, todos os projetos | seu fluxo pessoal |
| `project` | `.claude/settings.json` do repo | só quando quiser por repo |
| `local` | só neste repo (gitignored) | teste pontual |

Com escopo `user`, o MCP `context7` do plugin (`.mcp.json`) também fica
global — vale em todos os projetos, sem repetir instalação.

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

### Método npm (recomendado)

Os pacotes npm precisam estar publicados antes desta etapa. A implementação
local já está preparada na versão `0.4.0`.

Na tela **Install plugin**, escolha o escopo `global` e informe os pacotes:

```text
@nomadiction8991/fluxo-trabalho
@nomadiction8991/ai-memory
```

Ou execute:

```bash
opencode plugin --global @nomadiction8991/fluxo-trabalho@0.4.0
opencode plugin --global @nomadiction8991/ai-memory@0.4.0
```

O OpenCode instala os módulos npm e atualiza o `~/.config/opencode/opencode.json`.
Ao carregar, cada plugin registra automaticamente sua pasta de skills; o
`ai-memory` registra também o MCP remoto usando o arquivo de token, sem
embutir a credencial no pacote.

Depois configure o binário e o token do ai-memory com o instalador explícito:

```bash
npx --yes --package @nomadiction8991/ai-memory@0.4.0 ai-memory-setup
```

Esse comando pode solicitar o Bearer token e mantém a configuração do
Claude Code compatível. O `postinstall` do pacote não baixa binários, não
altera credenciais e não modifica configurações globais.

Reinicie Claude Code / OpenCode depois da instalação.

### Método legado automático

Com o repo já clonado (ou baixe direto), rode o instalador:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Nomadiction8991/MyMarketPlace/main/scripts/install-opencode.sh)
```

O script:
1. clona o marketplace em `~/marketplaces/MyMarketPlace` (se não existir);
2. mescla **no config global** (`~/.config/opencode/opencode.json`) —
   escopo de usuário, vale em todos os projetos;
3. garante `plugin` + `skills.paths` + **MCP context7**, **preservando**
   MCPs e outras configs existentes;
4. é idempotente — rodar de novo não duplica nada.

Depois reinicie o OpenCode.

### Método legado/manual

### 1. Clonar o marketplace

O OpenCode não tem "marketplace": ele carrega o plugin e as skills por
**caminho no disco**. Então clone o repo uma vez na sua máquina:

```bash
git clone https://github.com/Nomadiction8991/MyMarketPlace.git ~/marketplaces/MyMarketPlace
```

### 2. Apontar no `opencode.json` (global)

No config global `~/.config/opencode/opencode.json` (escopo de usuário):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["/home/SEU_USUARIO/marketplaces/MyMarketPlace/plugins/fluxo-trabalho/index.ts"],
  "skills": {
    "paths": ["/home/SEU_USUARIO/marketplaces/MyMarketPlace/plugins/fluxo-trabalho/skills"]
  }
}
```

Use o caminho absoluto do clone.

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

## MCP context7 (dependência do code-review)

A skill `code-review` consulta documentação atualizada com o MCP
**context7**. Ele vem assim:

- **Claude Code**: automático — o plugin traz um `.mcp.json` com o
  servidor `context7` (`npx -y @upstash/context7-mcp`). Ao instalar o
  plugin, o MCP já conecta; confirme com `/mcp`.
- **OpenCode**: adicione manualmente uma vez no `mcp` do config global
  (`~/.config/opencode/opencode.json`):

  ```json
  "context7": {
    "type": "remote",
    "url": "https://mcp.context7.com/mcp",
    "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}" },
    "enabled": true
  }
  ```

  (Sem `CONTEXT7_API_KEY` no ambiente, o context7 funciona com limite
  gratuito.) Depois reinicie o OpenCode.

---

## Plugin ai-memory (memória de longo prazo)

Plugin **cliente** do servidor ai-memory: registra o MCP remoto e emite
hooks de ciclo de vida (início/fim de sessão, prompts, ferramentas) para o
servidor em `https://aimemory.anvy.com.br`. A **credencial nunca fica no
plugin**: é lida em runtime de um arquivo de secrets.

### 1. Instalar o plugin

**Claude Code** (escopo usuário):

```
/plugin install ai-memory@my-marketplace
```

O plugin traz o `.mcp.json` (servidor MCP remoto com `headersHelper` que
lê o token do secrets file em runtime) + hooks + 6 skills embutidas. Com
o token salvo no secrets file, o MCP conecta sozinho.

**OpenCode legado**: adicione ao config global (`~/.config/opencode/opencode.json`):

```json
"plugin": [
  "/home/SEU_USUARIO/marketplaces/MyMarketPlace/plugins/ai-memory/index.ts"
]
```

### 2. Instalar binário + credencial (uma vez por máquina, método legado)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Nomadiction8991/MyMarketPlace/main/plugins/ai-memory/scripts/install.sh)
```

O script (idempotente, escopo usuário):

1. garante o clone do marketplace em `~/marketplaces/MyMarketPlace`
   (plugin + skills + hooks);
2. baixa o binário `ai-memory` do release oficial (sha256 conferido);
3. pergunta o **Bearer token** e salva em
   `~/.local/share/opencode/secrets/aimemory-token` (chmod 600) — ou use
   `AI_MEMORY_TOKEN=...` para não perguntar;
4. registra o MCP remoto no **Claude Code** (`claude mcp add --scope user`)
   e instala o plugin `ai-memory@my-marketplace` (skills embutidas);
5. mescla plugin + `skills.paths` + MCP remoto no config global do
   **OpenCode** (`"Authorization": "Bearer {file:...}"`).

Depois reinicie Claude Code / OpenCode.

> **Só baixar e colocar a credencial**: o plugin já sabe onde buscar o
> binário e o token em runtime. Se preferir, basta criar o arquivo
> `~/.local/share/opencode/secrets/aimemory-token` com o token (sem quebra
> de linha) — sem rodar o script — desde que o binário `ai-memory` já
> exista no `PATH` ou em `~/.local/bin`.
>
> Para apontar para outro servidor, exporte `AI_MEMORY_SERVER_URL` (hooks)
> ou defina no config do OpenCode.

### Skills (embutidas no plugin)

As 6 skills (`ai-memory-retrieval`, `ai-memory-handoff`,
`ai-memory-durable-pages`, `ai-memory-learning-maintenance`,
`ai-memory-routing-install` e `ai-memory-login`) são **vendidas dentro do
plugin**, em `plugins/ai-memory/skills/`:

- **Claude Code**: vêm junto com o plugin (auto-discovery, namespace
  `ai-memory:`) — instalar o plugin já traz as skills.
- **OpenCode npm**: o hook `config` do pacote registra a pasta vendida no
  config carregado, sem exigir edição manual.
- **OpenCode legado**: o `skills.paths` do `install.sh` aponta para a pasta
  vendida.

Não é preciso rodar `install-skills` — tudo vem no pacote.

### Credencial solicitada em runtime

O plugin **nunca leva a chave embutida**. Se o token não existir quando o
plugin rodar:

- **hooks/`emit.sh`** (Claude): avisa no stderr qual arquivo criar / qual
  instalador rodar, e sai sem bloquear;
- **`index.ts`** (OpenCode): mostra toast + injeta lembrete no system
  prompt para o agente pedir o token ao usuário;
- **skill `ai-memory-login`**: ensina o agente a pedir o token, salvá-lo
  em `~/.local/share/opencode/secrets/aimemory-token` (chmod 600) e testar
  a conexão.

### Hooks do Claude Code

O plugin traz `hooks/hooks.json` (SessionStart, UserPromptSubmit,
PreToolUse, PostToolUse, PreCompact, Stop, SessionEnd), todos apontando
para `hooks/emit.sh` — o mesmo runtime de resolução do `index.ts` do
OpenCode (env `AI_MEMORY_TOKEN` > arquivo de secrets).

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
