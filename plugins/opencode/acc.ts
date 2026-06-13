/**
 * acc OpenCode plugin — the CONSUMER side of the accreted scored memory (acc.db).
 *
 * OpenCode sessions USE and FEED the substrate; reasoning stays MaxSim-first in the
 * interactive session (the one reasoner). This plugin does two things only:
 *
 *   1. FEED — translate OpenCode lifecycle events into the ONE cross-host generic
 *      envelope and pipe them to `acc hook <event> --host generic`:
 *        session.created            → session-start   (child session → subagent-start)
 *        chat.message               → turn-start      (carries the prompt; the stdout —
 *                                                      the BINDING retrieval memo — is
 *                                                      surfaced back into the message
 *                                                      parts so the model SEES it)
 *        tool.execute.after         → post-tool       (tool_name/tool_input/tool_response)
 *        session.idle               → turn-end        (child session → subagent-end)
 *        session.compacted          → compact
 *        session.deleted            → session-end
 *      (OpenCode emits no event on plain process exit — session-end fires on explicit
 *      session deletion only; the acc ledger stays consistent either way.)
 *
 *   2. NEVER HURT — every handler is wrapped; a missing acc binary is a permanent
 *      silent no-op; a hung hook is killed after a timeout; the plugin can never crash
 *      or block the host.
 *
 * The two-verb MCP access (acc_retrieve / acc_act) is registered separately in
 * opencode.json — see opencode.json.snippet next to this file. Cross-project memory:
 * export ACC_DB=/abs/path/acc.db (the spawned hooks inherit the session environment).
 */
import type { Plugin } from "@opencode-ai/plugin"
import { spawn } from "node:child_process"

/** The acc binary name, OS-resolved: `acc.exe` on Windows (PATH-resolved via PATHEXT),
 * bare `acc` everywhere else. Keeps the plugin multi-OS without enabling a shell. */
const ACC_BIN = process.platform === "win32" ? "acc.exe" : "acc"

/** A hook call is bounded: retrieval injection can take a moment, but a wedged binary
 * must never wedge the host turn. */
const HOOK_TIMEOUT_MS = 15_000
/** The INTERACTIVE bound (reactivity, solved:70f7939452193e31): chat.message blocks the
 * user's prompt, so its hook gets a tight ceiling — the binary's own retrieve budget
 * (ACC_HOOK_RETRIEVE_BUDGET_MS, default 2s) returns well inside it; this is the backstop. */
const PROMPT_HOOK_TIMEOUT_MS = 4_000

/** The one cross-host envelope (matches `acc hook --host generic`; unknown keys are
 * ignored by the binary, session_id+cwd are required). */
type Envelope = {
  session_id: string
  cwd: string
  prompt?: string
  tool_name?: string
  tool_input?: unknown
  tool_response?: unknown
  agent_id?: string
}

export const AccPlugin: Plugin = async (input) => {
  const projectDir = input.directory
  /** acc not installed → permanent silent no-op (set on first ENOENT). */
  let binaryMissing = false
  /** child session id → parent session id (subagent tracking). */
  const children = new Map<string, string>()
  /** session id → its directory (sessions can live outside the project dir). */
  const dirs = new Map<string, string>()
  /** session id → ONE pending turn-end verdict (Stop guard / DIAGNOSIS / credit nudges),
   * surfaced as a message part on the NEXT prompt then dropped. BOUNDED: replaced, never
   * accumulated — the guard is as hard as the platform allows (it cannot block a stop,
   * but its verdict is never silently dropped again). */
  const pendingVerdict = new Map<string, string>()
  /** session id → its captured SessionStart warm briefing (open commitments, open
   * brain_frames, live laws, grounding). session.created is an event handler with no
   * output.parts surface, so the briefing stdout is held here and drained — exactly once
   * — onto the FIRST chat.message of the session (the documented fallback surface), then
   * dropped. BOUNDED: set once at session.created, deleted on first drain. */
  const pendingBriefing = new Map<string, string>()

  const dirFor = (sessionID: string): string => dirs.get(sessionID) ?? projectDir

  /** Spawn `acc hook <event> --host generic`, envelope on stdin. Resolves the hook's
   * stdout; NEVER rejects — any fault (missing binary, timeout, spawn error) → "". */
  const hook = (event: string, envelope: Envelope, timeoutMs: number = HOOK_TIMEOUT_MS): Promise<string> =>
    new Promise((resolve) => {
      if (binaryMissing) return resolve("")
      try {
        const child = spawn(ACC_BIN, ["hook", event, "--host", "generic"], {
          stdio: ["pipe", "pipe", "ignore"],
        })
        let out = ""
        const timer = setTimeout(() => {
          try {
            child.kill("SIGKILL")
          } catch {}
          resolve("")
        }, timeoutMs)
        child.on("error", (err: NodeJS.ErrnoException) => {
          if (err && err.code === "ENOENT") binaryMissing = true
          clearTimeout(timer)
          resolve("")
        })
        child.stdout?.on("data", (chunk) => {
          out += String(chunk)
        })
        child.on("close", () => {
          clearTimeout(timer)
          resolve(out)
        })
        child.stdin?.on("error", () => {}) // EPIPE on a fast exit must not throw
        child.stdin?.write(JSON.stringify(envelope))
        child.stdin?.end()
      } catch {
        resolve("")
      }
    })

  return {
    event: async ({ event }) => {
      try {
        switch (event.type) {
          case "session.created": {
            const info = event.properties.info
            dirs.set(info.id, info.directory)
            if (info.parentID) {
              children.set(info.id, info.parentID)
              void hook("subagent-start", {
                session_id: info.parentID,
                cwd: info.directory,
                agent_id: info.id,
                prompt: info.title ?? "",
              })
            } else {
              // session.created has no output.parts surface, so AWAIT the warm
              // session-start briefing and hold it for the first chat.message to inject
              // (the documented fallback surface). hook() NEVER rejects — a fault resolves
              // to "" — so nothing is held and session start is unaffected (fail-open).
              const briefing = await hook("session-start", {
                session_id: info.id,
                cwd: info.directory,
              })
              if (briefing.trim().length > 0) pendingBriefing.set(info.id, briefing.trim())
            }
            break
          }
          case "session.idle": {
            const sid = event.properties.sessionID
            const parent = children.get(sid)
            if (parent) {
              void hook("subagent-end", {
                session_id: parent,
                cwd: dirFor(sid),
                agent_id: sid,
              })
            } else {
              const verdict = await hook("turn-end", { session_id: sid, cwd: dirFor(sid) })
              if (verdict.trim().length > 0) pendingVerdict.set(sid, verdict.trim())
            }
            break
          }
          case "session.compacted": {
            const sid = event.properties.sessionID
            void hook("compact", { session_id: sid, cwd: dirFor(sid) })
            break
          }
          case "session.deleted": {
            const info = event.properties.info
            dirs.delete(info.id)
            // A subagent session closing is not a host session end.
            if (children.delete(info.id)) break
            void hook("session-end", { session_id: info.id, cwd: info.directory })
            break
          }
        }
      } catch {
        /* the plugin never crashes the host */
      }
    },

    "chat.message": async (inp, output) => {
      try {
        const sessionID = inp.sessionID ?? output.message.sessionID
        const prompt = output.parts
          .map((p) => (p.type === "text" && !p.synthetic ? p.text : ""))
          .filter((t) => t.trim().length > 0)
          .join("\n")
        const memo = await hook(
          "turn-start",
          { session_id: sessionID, cwd: dirFor(sessionID), prompt },
          PROMPT_HOOK_TIMEOUT_MS,
        )
        // Surface the captured SessionStart warm briefing FIRST, exactly once — on the
        // first chat.message of the session (session.created had no parts surface to
        // inject it). The delete IS the once-flag: drained here, normal behavior resumes.
        const briefing = pendingBriefing.get(sessionID)
        if (briefing) {
          pendingBriefing.delete(sessionID)
          output.parts.push({
            id: `prt_accs_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
            sessionID: output.message.sessionID,
            messageID: output.message.id,
            type: "text",
            text: `[acc session-start briefing]\n${briefing}`,
            synthetic: true,
          })
        }
        // Surface the PREVIOUS turn's carried verdict first (one pending entry, then
        // dropped) — the turn-end guard's voice on a platform that cannot block a stop.
        const carried = pendingVerdict.get(sessionID)
        if (carried) {
          pendingVerdict.delete(sessionID)
          output.parts.push({
            id: `prt_accv_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
            sessionID: output.message.sessionID,
            messageID: output.message.id,
            type: "text",
            text: `[acc turn-end verdict — previous turn]\n${carried}`,
            synthetic: true,
          })
        }
        // Surface the BINDING retrieval memo back into the turn (the top law: knowledge
        // compounds only when retrieval is behaviorally binding — the model must SEE it).
        if (memo.trim().length > 0) {
          output.parts.push({
            id: `prt_acc_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
            sessionID: output.message.sessionID,
            messageID: output.message.id,
            type: "text",
            text: memo.trimEnd(),
            synthetic: true,
          })
        }
      } catch {
        /* never crash the host */
      }
    },

    "tool.execute.after": async (inp, output) => {
      try {
        // acc's verify-evidence matcher keys on the Claude Code tool name "Bash";
        // OpenCode's shell tool is "bash" — normalize so cargo test/nextest runs in
        // OpenCode sessions feed the same outcome link.
        const tool_name = inp.tool === "bash" ? "Bash" : inp.tool
        const meta = (output?.metadata ?? {}) as Record<string, unknown>
        const exit = [meta["exit"], meta["exit_code"], meta["code"]].find(
          (x) => typeof x === "number",
        )
        const tool_response =
          typeof exit === "number"
            ? { exit_code: exit }
            : { output: String(output?.output ?? "").slice(0, 4000) }
        void hook("post-tool", {
          session_id: inp.sessionID,
          cwd: dirFor(inp.sessionID),
          tool_name,
          tool_input: inp.args ?? {},
          tool_response,
        })
      } catch {
        /* never crash the host */
      }
    },
  }
}
