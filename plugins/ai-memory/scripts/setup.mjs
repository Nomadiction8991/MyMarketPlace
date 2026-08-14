#!/usr/bin/env node
import { spawnSync } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

if (process.platform === "win32") {
  console.error("O setup do ai-memory usa o instalador Bash e atualmente requer Linux ou macOS.")
  process.exit(1)
}

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const installer = join(packageRoot, "scripts", "install.sh")
const result = spawnSync("bash", [installer, ...process.argv.slice(2)], {
  env: { ...process.env, AI_MEMORY_NPM_MODE: "1" },
  stdio: "inherit",
})

if (result.error) {
  console.error(`Não foi possível executar o instalador: ${result.error.message}`)
  process.exit(1)
}

process.exit(result.status ?? 1)
