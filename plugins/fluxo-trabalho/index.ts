import type { Plugin } from "@opencode-ai/plugin"
import type { Part } from "@opencode-ai/sdk"
import { createHash } from "node:crypto"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { writeFile } from "node:fs/promises"

const PLUGIN_ROOT = dirname(fileURLToPath(import.meta.url))
const RUN_SCRIPT = join(PLUGIN_ROOT, "hooks", "run.sh")
const INTERVIEW_REMINDER =
  "Antes de iniciar qualquer ação (pesquisa, edição ou implementação), execute a skill entreviste-me para validar o entendimento do pedido."

const editFlagPath = (worktree: string): string => {
  const key = createHash("md5").update(worktree).digest("hex").slice(0, 8)
  return join(process.env.TMPDIR ?? "/tmp", `fluxo-edited-${key}.flag`)
}

export const WorkflowHook: Plugin = async ({ $, worktree }) => {
  return {
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
