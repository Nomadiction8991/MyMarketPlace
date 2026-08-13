// Plugin OpenCode do ai-memory (cliente do servidor remoto).
// Porta do plugin gerado por `ai-memory install-hooks --agent open-code`,
// com a diferença: SERVER e TOKEN são resolvidos em runtime (env > arquivo
// de secrets), nunca embutidos no código.
//
// Resolução:
//   SERVER: env AI_MEMORY_SERVER_URL (padrão https://aimemory.anvy.com.br)
//   TOKEN:  env AI_MEMORY_TOKEN  >  ~/.local/share/opencode/secrets/aimemory-token

import type { Plugin } from "@opencode-ai/plugin";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { homedir } from "node:os";

const SERVER = (process.env.AI_MEMORY_SERVER_URL || "https://aimemory.anvy.com.br").replace(/\/+$/, "");
const AGENT = "open-code";
const TOKEN_FILE = process.env.AI_MEMORY_TOKEN_FILE || join(homedir(), ".local", "share", "opencode", "secrets", "aimemory-token");

let cachedToken: string | null | undefined;
function resolveToken(): string | null {
  if (cachedToken !== undefined) return cachedToken;
  if (process.env.AI_MEMORY_TOKEN) {
    cachedToken = process.env.AI_MEMORY_TOKEN;
    return cachedToken;
  }
  try {
    if (existsSync(TOKEN_FILE)) {
      cachedToken = readFileSync(TOKEN_FILE, "utf8").trim() || null;
      return cachedToken;
    }
  } catch (_e) {
    // cai no null abaixo
  }
  cachedToken = null;
  return null;
}

function timeoutSignal(ms: number): AbortSignal | undefined {
  if (typeof AbortSignal === "undefined") return undefined;
  const factory = (AbortSignal as unknown as { timeout?: (ms: number) => AbortSignal }).timeout;
  return factory ? factory(ms) : undefined;
}

function authHeaders(): Record<string, string> {
  const token = resolveToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function findMarker(cwd: string | undefined): string | undefined {
  if (!cwd) return undefined;
  let dir = resolve(cwd);
  const home = homedir();
  while (dir && dir !== dirname(dir)) {
    const marker = join(dir, ".ai-memory.toml");
    if (existsSync(marker)) return marker;
    if (home && dir === home) return undefined;
    dir = dirname(dir);
  }
  return undefined;
}

function tomlKey(text: string, key: string): string | undefined {
  const re = new RegExp(`^\\s*${key}\\s*=\\s*"([^"]*)"`);
  for (const line of text.split(/\r?\n/)) {
    const match = re.exec(line);
    if (match) return match[1];
  }
  return undefined;
}

function repoRootProject(cwd: string | undefined): string | undefined {
  if (!cwd) return undefined;
  try {
    const inside = execFileSync("git", ["-C", cwd, "rev-parse", "--is-inside-work-tree"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (inside !== "true") return undefined;
    const common = execFileSync("git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (!common) return undefined;
    const root = dirname(common);
    if (!root || root === dirname(root)) return undefined;
    return basename(root);
  } catch (_e) {
    return undefined;
  }
}

function applyMarkerParams(url: URL, cwd: string | undefined): void {
  const marker = findMarker(cwd);
  if (!marker || !cwd) return;
  url.searchParams.set("cwd", cwd);
  try {
    const body = readFileSync(marker, "utf8");
    const workspace = tomlKey(body, "workspace");
    const project = tomlKey(body, "project");
    const projectStrategy = tomlKey(body, "project_strategy");
    if (workspace) url.searchParams.set("workspace", workspace);
    if (project) url.searchParams.set("project", project);
    if (projectStrategy) url.searchParams.set("project_strategy", projectStrategy);
    if (!project && (projectStrategy === "repo-root" || projectStrategy === "repo_root")) {
      const repoProject = repoRootProject(cwd);
      if (repoProject) url.searchParams.set("project", repoProject);
    }
  } catch (_e) {
  }
}

function sessionID(input: unknown): string | undefined {
  const value = input as any;
  return value?.sessionID ?? value?.sessionId ?? value?.session_id ?? value?.info?.id;
}

function textFromParts(parts: unknown): string {
  if (!Array.isArray(parts)) return "";
  return parts
    .map((part: any) => {
      if (part?.type === "text" && typeof part.text === "string") return part.text;
      if (part?.type === "subtask" && typeof part.prompt === "string") return part.prompt;
      if (part?.type === "file" && typeof part.filename === "string") return `[file: ${part.filename}]`;
      return "";
    })
    .filter(Boolean)
    .join("\n\n")
    .trim();
}

const sessionCwds = new Map<string, string>();
const startedSessions = new Set<string>();
const handoffChecked = new Set<string>();
const preCompactLast = new Map<string, number>();
const missingCredentialWarned = new Set<string>();
let opencodeClient: { tui?: { showToast?: (opts: unknown) => Promise<unknown> } } | undefined;
const CREDENTIAL_HINT =
  "⚠ ai-memory: credencial ausente (token não encontrado em AI_MEMORY_TOKEN nem em ~/.local/share/opencode/secrets/aimemory-token). " +
  "Solicite o token ao usuário e, com a permissão dele, salve-o (sem quebra de linha, chmod 600) no arquivo " +
  "~/.local/share/opencode/secrets/aimemory-token — ou rode o instalador: " +
  "bash <(curl -fsSL https://raw.githubusercontent.com/Nomadiction8991/MyMarketPlace/main/plugins/ai-memory/scripts/install.sh).";

function warnMissingCredential(input: unknown): void {
  const id = sessionID(input) ?? "unknown";
  if (missingCredentialWarned.has(id)) return;
  missingCredentialWarned.add(id);
  if (resolveToken() !== null) return;
  try {
    if (opencodeClient?.tui?.showToast) {
      void opencodeClient.tui
        .showToast({
          body: {
            title: "ai-memory: credencial ausente",
            message: "Peça o token ao usuário ou rode o instalador (veja logs).",
            variant: "warning",
          },
        })
        .catch(() => undefined);
    }
  } catch (_e) {
    // aviso silencioso
  }
  console.error(CREDENTIAL_HINT);
}

function cwdFor(id: string | undefined, directory: string): string {
  return (id && sessionCwds.get(id)) || directory;
}

function rememberCwd(id: string | undefined, cwd: string | undefined): void {
  if (id && cwd) sessionCwds.set(id, cwd);
}

function startSession(id: string | undefined, cwd: string, extra: Record<string, unknown> = {}): void {
  if (!id || startedSessions.has(id)) return;
  startedSessions.add(id);
  rememberCwd(id, cwd);
  postHook("session-start", { sessionID: id, cwd, ...extra });
}

function postPreCompact(id: string | undefined, directory: string): void {
  startSession(id, cwdFor(id, directory));
  const key = id || "unknown";
  const now = Date.now();
  const last = preCompactLast.get(key) ?? 0;
  if (now - last < 1000) return;
  preCompactLast.set(key, now);
  postHook("pre-compact", { sessionID: id, cwd: cwdFor(id, directory) });
}

function postHook(event: string, payload: Record<string, unknown>): void {
  const url = new URL(`${SERVER}/hook`);
  url.searchParams.set("event", event);
  url.searchParams.set("agent", AGENT);
  applyMarkerParams(url, typeof payload.cwd === "string" ? payload.cwd : undefined);
  try {
    void fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body: JSON.stringify(payload),
      signal: timeoutSignal(500),
    }).catch(() => undefined);
  } catch (_e) {
    // Fire-and-forget. Hooks must never block the agent.
  }
}

async function fetchHandoff(cwd: string): Promise<string | undefined> {
  const url = new URL(`${SERVER}/handoff`);
  url.searchParams.set("agent", AGENT);
  url.searchParams.set("cwd", cwd);
  applyMarkerParams(url, cwd);
  try {
    const response = await fetch(url, {
      headers: authHeaders(),
      signal: timeoutSignal(1000),
    });
    const text = (await response.text()).trim();
    return text.length > 0 ? text : undefined;
  } catch (_e) {
    return undefined;
  }
}

export const AiMemoryHooks: Plugin = async ({ directory, client }) => {
  opencodeClient = client as typeof opencodeClient;
  return {
    event: async (input) => {
      const event = (input as any).event;
      const properties = event?.properties ?? {};
      if (event?.type === "session.created") {
        const info = properties.info ?? {};
        const id = properties.sessionID ?? info.id;
        const cwd = info.directory ?? directory;
        warnMissingCredential(input);
        startSession(id, cwd, {
          title: info.title,
          projectID: info.projectID,
        });
      }
      if (event?.type === "session.idle") {
        const id = properties.sessionID;
        startSession(id, cwdFor(id, directory));
        postHook("stop", { sessionID: id, cwd: cwdFor(id, directory) });
      }
      if (event?.type === "session.compacted") {
        const id = properties.sessionID;
        postPreCompact(id, directory);
      }
    },
    "chat.message": async (input, output) => {
      const id = sessionID(input);
      const cwd = cwdFor(id, directory);
      warnMissingCredential(input);
      startSession(id, cwd, { agent: (input as any).agent, model: (input as any).model });
      postHook("user-prompt", {
        sessionID: id,
        cwd,
        agent: (input as any).agent,
        model: (input as any).model,
        messageID: (input as any).messageID,
        prompt: textFromParts((output as any).parts),
      });
    },
    "tool.execute.before": async (input, output) => {
      const id = sessionID(input);
      startSession(id, cwdFor(id, directory));
      postHook("pre-tool-use", {
        sessionID: id,
        cwd: cwdFor(id, directory),
        tool: (input as any).tool,
        callID: (input as any).callID,
        args: (output as any).args,
      });
    },
    "tool.execute.after": async (input, output) => {
      const id = sessionID(input);
      startSession(id, cwdFor(id, directory));
      postHook("post-tool-use", {
        sessionID: id,
        cwd: cwdFor(id, directory),
        tool: (input as any).tool,
        callID: (input as any).callID,
        args: (input as any).args,
        title: (output as any).title,
        output: (output as any).output,
        metadata: (output as any).metadata,
      });
    },
    "experimental.session.compacting": async (input) => {
      const id = sessionID(input);
      postPreCompact(id, directory);
    },
    "experimental.chat.system.transform": async (input, output) => {
      const id = sessionID(input);
      if (!id || handoffChecked.has(id)) return;
      handoffChecked.add(id);
      if (resolveToken() === null) (output as any).system.push(CREDENTIAL_HINT);
      startSession(id, cwdFor(id, directory));
      const handoff = await fetchHandoff(cwdFor(id, directory));
      if (handoff) (output as any).system.push(handoff);
    },
  };
};

export default AiMemoryHooks;
