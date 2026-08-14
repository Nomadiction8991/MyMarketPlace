import type { Plugin } from "@opencode-ai/plugin"
import type { Part } from "@opencode-ai/sdk"
import { readFile, writeFile, chmod } from "node:fs/promises"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const PLUGIN_ROOT = dirname(fileURLToPath(import.meta.url))
const SKILLS_PATH = join(PLUGIN_ROOT, "skills")
const CONTROL_SCRIPT = join(PLUGIN_ROOT, "scripts", "opencode-control.py")
const CONTROLS = ["status", "aplicar", "remover", "token"]

const LIMIT_PATTERNS = [
  /you(?:'|’)ve hit (?:your )?(?:usage|message|session) limit/i,
  /hit (?:your )?(?:usage|message|session) limit/i,
  /usage limit (?:reached|exceeded)/i,
  /rate limit (?:reached|exceeded)/i,
  /message limit (?:reached|exceeded)/i,
  /session limit (?:reached|exceeded)/i,
  /limite (?:de uso|da sess(?:a|ã)o|de mensagens).*(?:atingido|excedido)/i,
  /(?:perto|prestes?) de atingir .*limite/i,
]

type OpenCodeConfig = {
  skills?: { paths?: string[] }
}

function addSkillPath(config: OpenCodeConfig): void {
  config.skills ??= {}
  config.skills.paths ??= []
  if (!config.skills.paths.includes(SKILLS_PATH)) config.skills.paths.push(SKILLS_PATH)
}

function secretsTokenPath(): string {
  return join(homedir(), ".local", "share", "opencode", "secrets", "9router-token")
}

function shellText(result: unknown): string {
  if (typeof result === "string") return result
  const r = result as { stdout?: unknown; stderr?: unknown }
  const stdout = r?.stdout
  if (typeof stdout === "string") return stdout
  if (stdout instanceof Buffer) return stdout.toString()
  const stderr = r?.stderr
  if (typeof stderr === "string") return stderr
  if (stderr instanceof Buffer) return stderr.toString()
  return "Comando executado sem saída."
}

function userText(parts: Part[]): string {
  return parts
    .filter((p): p is Extract<Part, { type: "text" }> => p.type === "text")
    .map((p) => p.text)
    .join(" ")
}

export const NineRouterProvider: Plugin = async ({ $, worktree }) => {
  return {
    config: async (config) => {
      const mutable = config as OpenCodeConfig
      addSkillPath(mutable)
      if (!process.env.NINEROUTER_KEY) {
        try {
          const token = (await readFile(secretsTokenPath(), "utf-8")).trim()
          if (token) process.env.NINEROUTER_KEY = token
        } catch {
          try {
            const legacy = (await readFile(join(homedir(), ".claude", "limit-proxy-token"), "utf-8")).trim()
            if (legacy) process.env.NINEROUTER_KEY = legacy
          } catch {
            /* sem token ainda — /9router token ou env resolve */
          }
        }
      }
    },

    "chat.message": async (_input, output) => {
      const trimmed = userText(output.parts).trim()
      const keyMatch = /^token\s+(sk-\S+)\s*$/.exec(trimmed)
      if (keyMatch) {
        const path = secretsTokenPath()
        await writeFile(path, keyMatch[1] + "\n", { mode: 0o600 })
        await chmod(path, 0o600).catch(() => {})
        process.env.NINEROUTER_KEY = keyMatch[1]
        output.parts.push({
          type: "text",
          text: "[9router] Chave salva em ~/.local/share/opencode/secrets/9router-token (600). A troca de provider será aplicada ao detectar o próximo limite.",
        } as Part)
        return
      }
      if (trimmed === "/9router" || trimmed.startsWith("/9router ")) {
        const args = trimmed.slice("/9router".length).trim().split(/\s+/)
        const action = args[0]?.toLowerCase() ?? "status"
        let mapped = action
        if (action === "on" || action === "ativar") mapped = "aplicar"
        if (action === "off" || action === "desativar") mapped = "remover"
        if (!CONTROLS.includes(mapped)) {
          output.parts.push({ type: "text", text: "Uso: /9router [status|aplicar|remover|token]" } as Part)
          return
        }
        const result = await $`python3 ${CONTROL_SCRIPT} ${mapped}`.cwd(worktree).nothrow()
        const text = shellText(result)
        output.parts.push({ type: "text", text: `[9router]\n${text.trim()}` } as Part)
        return
      }

      if (!LIMIT_PATTERNS.some((pattern) => pattern.test(trimmed))) return

      if (!process.env.NINEROUTER_KEY) {
        output.parts.push({
          type: "text",
          text: "[9router] Limite de uso detectado, mas não encontrei a chave do 9router. Cole sua chave respondendo: token <sk-...> — ela será salva em ~/.local/share/opencode/secrets/9router-token (600) e a troca de provider aplicada em seguida.",
        } as Part)
        return
      }

      const result = await $`python3 ${CONTROL_SCRIPT} aplicar`.cwd(worktree).nothrow()
      const text = shellText(result)
      output.parts.push({
        type: "text",
        text: `[9router] Limite de uso detectado. ${text.trim()}`,
      } as Part)
    },
  }
}