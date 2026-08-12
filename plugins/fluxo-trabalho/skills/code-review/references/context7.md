# Context7 MCP Global

A skill depende do MCP `context7` para consultar documentação atualizada antes da revisão.

## Regra de uso

Antes de revisar, identifique as tecnologias presentes no diff e use `context7` para buscar documentação atualizada das bibliotecas, frameworks, SDKs ou CLIs relevantes.

Se o MCP `context7` não estiver disponível, instale e configure automaticamente em escopo global antes de continuar. Preserve configurações existentes e não sobrescreva arquivos sem ler/mesclar.

## Claude Code

Verifique se o servidor existe:

```bash
claude mcp list
```

Se `context7` não existir, instale globalmente para o usuário:

```bash
claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp
```

Não use `--scope project` nem escreva `.mcp.json` no projeto, salvo se o usuário pedir explicitamente escopo por projeto.

Se o usuário tiver `CONTEXT7_API_KEY`, prefira configurar globalmente com header via JSON:

```bash
claude mcp add-json --scope user context7 '{"type":"http","url":"https://mcp.context7.com/mcp","headers":{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}}'
```

Depois, peça para reiniciar/recarregar a sessão se as ferramentas MCP ainda não aparecerem.

## opencode

Verifique somente a configuração global: `~/.config/opencode/opencode.json` ou `~/.config/opencode/opencode.jsonc`.

Se `context7` não existir, mescle este bloco no `mcp` global:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "enabled": true
    }
  }
}
```

Se o usuário tiver `CONTEXT7_API_KEY`, use no config global:

```json
{
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
      },
      "enabled": true
    }
  }
}
```

Não altere `opencode.json`/`opencode.jsonc` do projeto, salvo se o usuário pedir explicitamente escopo por projeto.

Depois de alterar a configuração global, reinicie o opencode.
