// Emba for opencode: tells Emba what each session is doing, and lets Emba
// answer permission prompts. Installed by `emba connect opencode` into
// ~/.config/opencode/plugins/. Emba not running -> every call is a quiet no-op.
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

export const Emba = async ({ directory }) => {
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
