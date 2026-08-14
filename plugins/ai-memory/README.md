# ai-memory para OpenCode e Claude Code

## OpenCode

Instale o plugin npm no escopo global:

```bash
opencode plugin --global @nomadiction8991/ai-memory@0.4.0
```

O plugin registra as 6 skills e o MCP remoto no carregamento do OpenCode.

## Configuração completa

O plugin não baixa binários nem pede segredos durante o carregamento. Para
configurar o binário, o token e a integração do Claude Code, execute:

```bash
npx --yes --package @nomadiction8991/ai-memory@0.4.0 ai-memory-setup
```

O token é salvo em `~/.local/share/opencode/secrets/aimemory-token` com
permissão `600`. Também é possível usar `AI_MEMORY_TOKEN` sem prompt.

## Claude Code

O pacote npm é o adaptador do OpenCode. Para o Claude Code, use o marketplace
nativo:

```text
/plugin marketplace add Nomadiction8991/MyMarketPlace
/plugin install ai-memory@my-marketplace
```
