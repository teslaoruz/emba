// Emba for opencode: tells Emba what each session is doing, and lets Emba
// answer permission prompts. Installed by `emba connect opencode` into
// ~/.config/opencode/plugins/. Emba not running -> every call is a quiet no-op.
// Speaks both plugin APIs from one default export: opencode 1.x calls `server`,
// opencode 2 reads `id` and `setup`.
import net from "node:net"
import os from "node:os"
import path from "node:path"

// opencode shows its own prompt only after this plugin returns, so Emba gets
// a short window to answer before the decision goes back to the terminal.
const ANSWER_WINDOW_MS = 30_000

function address() {
  if (process.platform === "win32") return `\\\\.\\pipe\\emba-${os.userInfo().username}`
  const run = process.env.XDG_RUNTIME_DIR
  return run ? path.join(run, "emba.sock") : path.join(os.tmpdir(), `emba-${process.getuid()}.sock`)
}

// One JSON line out; with `wait`, one JSON line back (or null on any failure).
function send(msg, wait = false) {
  return new Promise((resolve) => {
    let buf = ""
    let done = false
    const finish = (v) => {
      if (done) return
      done = true
      sock.destroy()
      resolve(v)
    }
    const sock = net.connect(address())
    sock.setTimeout(300, () => finish(null))
    sock.on("error", () => finish(null))
    sock.on("close", () => finish(null))
    sock.on("connect", () => {
      sock.write(JSON.stringify(msg) + "\n")
      if (!wait) return sock.end()
      sock.setTimeout(ANSWER_WINDOW_MS, () => finish(null))
    })
    sock.on("data", (d) => {
      buf += d
      const i = buf.indexOf("\n")
      if (i < 0) return
      try {
        finish(JSON.parse(buf.slice(0, i)))
      } catch {
        finish(null)
      }
    })
  })
}

function target(tool, args = {}) {
  for (const k of ["command", "filePath", "file_path", "path", "url", "pattern", "query", "description"])
    if (args[k]) return String(k.toLowerCase().includes("path") ? path.basename(String(args[k])) : args[k]).slice(0, 300)
  return ""
}

const safe = (s) => String(s ?? "").replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120)

// ---- opencode 1.x ----
const Emba = async ({ directory }) => {
  const base = { agent: "opencode", cwd: directory, pid: process.pid }
  const sid = (id) => `opencode-${safe(id)}`

  return {
    event: async ({ event }) => {
      const p = event.properties ?? {}
      if (event.type === "session.created")
        await send({ ...base, ev: "SessionStart", sid: sid(p.info?.id), cwd: p.info?.directory || directory })
      else if (event.type === "session.deleted") await send({ ...base, ev: "SessionEnd", sid: sid(p.info?.id) })
      else if (event.type === "session.idle") await send({ ...base, ev: "Stop", sid: sid(p.sessionID), text: "" })
    },

    "chat.message": async (input, output) => {
      const text = (output.parts ?? []).filter((x) => x.type === "text").map((x) => x.text).join(" ")
      await send({ ...base, ev: "UserPromptSubmit", sid: sid(input.sessionID), target: text.slice(0, 300) })
    },

    "tool.execute.before": async (input, output) => {
      await send({ ...base, ev: "PreToolUse", sid: sid(input.sessionID), tool: input.tool, target: target(input.tool, output.args) })
    },

    "permission.ask": async (input, output) => {
      const pattern = Array.isArray(input.pattern) ? input.pattern.join(" ") : input.pattern ?? ""
      const reply = await send(
        {
          ...base,
          ev: "PermissionRequest",
          sid: sid(input.sessionID),
          id: safe(input.id) || `opencode-${Date.now()}`,
          tool: input.type,
          full: [input.title, pattern].filter(Boolean).join("\n"),
          always: false,
        },
        true,
      )
      if (reply?.behavior === "allow" || reply?.behavior === "deny") output.status = reply.behavior
    },
  }
}

// ---- opencode 2 ----
// Tool ids look like "functions.shell:2"; the event stream has no tool name of its own.
const v2tool = (id) => String(id ?? "").replace(/^functions\./, "").replace(/:\d+$/, "")

async function setup(ctx) {
  const directory = ctx.location?.directory ?? process.cwd()
  const base = { agent: "opencode", cwd: directory, pid: process.pid }
  const sid = (id) => `opencode-${safe(id)}`
  const last = new Map() // session -> its latest reply, sent when the turn ends
  const controller = new AbortController()

  ;(async () => {
    for await (const e of ctx.event.subscribe({ signal: controller.signal })) {
      const d = e.data ?? {}
      if (e.type === "session.created")
        send({ ...base, ev: "SessionStart", sid: sid(d.sessionID), cwd: d.location?.directory || directory })
      else if (e.type === "session.text.ended") last.set(d.sessionID, d.text ?? "")
      else if (e.type === "session.execution.succeeded" || e.type === "session.execution.failed") {
        send({ ...base, ev: "Stop", sid: sid(d.sessionID), text: String(last.get(d.sessionID) ?? "").slice(0, 2000) })
        last.delete(d.sessionID)
      } else if (e.type === "session.deleted") send({ ...base, ev: "SessionEnd", sid: sid(d.sessionID) })
    }
  })().catch(() => {})

  // not awaited: awaiting these in setup stalls opencode 2.0.21
  void ctx.session.hook("prompt", async (e) => {
    await send({ ...base, ev: "UserPromptSubmit", sid: sid(e.sessionID), target: String(e.prompt?.text ?? "").replace(/^"(.*)"$/s, "$1").slice(0, 300) })
  })
  void ctx.tool.hook("execute.before", async (e) => {
    if (e.tool === "execute") return // a code-mode wrapper; the real tool follows
    await send({ ...base, ev: "PreToolUse", sid: sid(e.sessionID), tool: e.tool || v2tool(e.id), target: target(e.tool, e.input) })
  })
  // Only questions opencode would ask anyway reach Emba; no answer leaves the terminal prompt.
  void ctx.permission.hook("evaluate", async (e) => {
    if (e.effect !== "ask") return
    const resources = (e.resources ?? []).join(" ")
    const reply = await send(
      {
        ...base,
        ev: "PermissionRequest",
        sid: sid(e.sessionID),
        id: safe(e.source?.id) || `opencode-${Date.now()}`,
        tool: e.action,
        full: resources.slice(0, 2000),
        always: false,
      },
      true,
    )
    if (reply?.behavior === "allow" || reply?.behavior === "deny") {
      e.effect = reply.behavior
      if (reply.behavior === "deny") e.message = "Denied from Emba."
    }
  })
  return () => controller.abort()
}

export default { id: "emba", setup, server: Emba }
