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
}

function addSkillPath(config: OpenCodeConfig): void {
  config.skills ??= {}
  config.skills.paths ??= []
  if (!config.skills.paths.includes(SKILLS_PATH)) config.skills.paths.push(SKILLS_PATH)
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
