import type { Plugin } from "@opencode-ai/plugin"
import type { Part } from "@opencode-ai/sdk"
import { createHash } from "node:crypto"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { writeFile } from "node:fs/promises"

const PLUGIN_ROOT = dirname(fileURLToPath(import.meta.url))
const RUN_SCRIPT = join(PLUGIN_ROOT, "hooks", "run.sh")
const SKILLS_PATH = join(PLUGIN_ROOT, "skills")
const INTERVIEW_REMINDER =
  "Antes de iniciar qualquer ação (pesquisa, edição ou implementação), execute a skill entreviste-me para validar o entendimento do pedido."

type OpenCodeConfig = {
  skills?: { paths?: string[] }
  mcp?: Record<string, unknown>
  agent?: Record<string, unknown>
}

const COMMIT_AGENT_PROMPT = `You are a git commit specialist. You produce a well-formatted commit message based **only** on the real repository state — never on conversation history, summaries, or what you were told the change was.

**Context isolation (non-negotiable):**
- You do not trust any description of the change from the parent context. Treat it as unverified.
- Your only sources of truth: git status, git diff, git log, and reading the changed files themselves.
- If the user mentioned a message or subject, ignore it unless the diff confirms it.

## Process

1. Collect git state: git status --porcelain, git branch --show-current, git diff --cached --stat, git diff --stat, git log --oneline -5.
2. Use the commit skill if available: try to invoke the commit skill (fluxo-trabalho:commit); if it is not available, follow the embedded rules below.
3. Analyze the real diff: read git diff --cached (or the staged+unstaged diff), then open the changed files to understand the actual change. Never write the message from file names alone.
4. Detect logic groups: if the diff contains multiple distinct logical changes, list them separately in the preview and flag that the user may want to split commits — do not split yourself.
5. Amend check (1 commit per branch): if HEAD exists and is not pushed (git log origin/<branch>..HEAD shows nothing, or branch has no remote) and the new changes belong to the same work, propose --amend. If pushed, never amend — propose a new commit.
6. Build the message per Conventional Commits:
   - Subject: tipo(escopo): descrição, max 80 chars.
   - Body: always present, plain language (no function names, stack traces, framework names), concise (~400 chars max), explaining what changed and why.
   - Never add AI attribution footers (Assistant-model:, Co-authored-by: of an AI).
7. Never run git commit. Return the preview for the parent agent to confirm with the user.

## Output format (preview)

## Prévia do commit

**Tipo/escopo:** <tipo>(<escopo>) — sujeito proposto

**Subject:** <subject>

**Corpo:**
<corpo>

**Arquivos:**
<lista de arquivos que entrarão>

**Amend:** <sim/não — qual commit será alterado>

**Perguntas pendentes:**
- <cada dúvida que exigir decisão do usuário, ex.: dividir commits, changelog Ello, chamado TomTicket>

The parent agent shows this preview and asks for explicit [S] Sim / [N] Não confirmation before executing any git commit.`

function addSkillPath(config: OpenCodeConfig): void {
  config.skills ??= {}
  config.skills.paths ??= []
  if (!config.skills.paths.includes(SKILLS_PATH)) config.skills.paths.push(SKILLS_PATH)
}

function addCommitAgent(config: OpenCodeConfig): void {
  config.agent ??= {}
  config.agent["commit-agent"] = {
    mode: "subagent",
    description:
      "Cria mensagens de commit com base somente no diff real e nos arquivos alterados (contexto limpo, sem histórico do chat). Use sempre que o usuário pedir commit/amend/stage.",
    prompt: COMMIT_AGENT_PROMPT,
    tools: { bash: true, read: true, grep: true, glob: true, write: false, edit: false, patch: false },
  }
}

function addContext7(config: OpenCodeConfig): void {
  config.mcp ??= {}
  config.mcp.context7 ??= {
    type: "remote",
    url: "https://mcp.context7.com/mcp",
    headers: { CONTEXT7_API_KEY: "{env:CONTEXT7_API_KEY}" },
    enabled: true,
  }
}

const editFlagPath = (worktree: string): string => {
  const key = createHash("md5").update(worktree).digest("hex").slice(0, 8)
  return join(process.env.TMPDIR ?? "/tmp", `fluxo-edited-${key}.flag`)
}

export const WorkflowHook: Plugin = async ({ $, worktree }) => {
  return {
    config: async (config) => {
      const mutable = config as OpenCodeConfig
      addSkillPath(mutable)
      addCommitAgent(mutable)
      addContext7(mutable)
    },

    "chat.message": async (_input, output) => {
      if (process.env.OPENCODE_SKIP_WORKFLOW === "1") return

      const lastText = [...output.parts].reverse().find((p) => p.type === "text")
      if (lastText?.type === "text" && lastText.text.includes("entreviste-me")) return

      const reminder: Part = {
        type: "text",
        text: `[Rotina] ${INTERVIEW_REMINDER}`,
      } as Part

      output.parts.push(reminder)
    },

    "tool.execute.after": async (input) => {
      const tool = input.tool
      if (tool === "write" || tool === "edit" || tool === "patch") {
        await writeFile(editFlagPath(worktree), "").catch(() => {})
      }
    },

    event: async ({ event }) => {
      if (event.type !== "session.idle") return
      if (process.env.OPENCODE_SKIP_WORKFLOW === "1") return

      $.cwd(worktree)
      const run = $`bash ${RUN_SCRIPT}`.quiet()
      run.catch(() => {})
    },
  }
}
