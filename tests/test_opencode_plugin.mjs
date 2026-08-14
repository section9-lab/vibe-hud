import assert from "node:assert/strict"
import fs from "node:fs/promises"
import net from "node:net"
import os from "node:os"
import path from "node:path"

const repoRoot = path.resolve(import.meta.dirname, "..")
const pluginPath = path.join(repoRoot, "VibeHUD/Resources/vibe-hud.js")
const socketPath = path.join(os.tmpdir(), `vibe-hud-test-${process.pid}.sock`)

const source = (await fs.readFile(pluginPath, "utf8")).replace(
  'const SOCKET_PATH = "/tmp/vibe-hud.sock"',
  `const SOCKET_PATH = ${JSON.stringify(socketPath)}`,
)
const moduleURL = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const pluginFactory = (await import(moduleURL)).default
const plugin = await pluginFactory()

const server = net.createServer()
await new Promise((resolve) => server.listen(socketPath, resolve))

async function captureEvent(input) {
  const received = new Promise((resolve) => {
    server.once("connection", (socket) => {
      let body = ""
      socket.on("data", (chunk) => { body += chunk.toString("utf8") })
      socket.on("end", () => resolve(JSON.parse(body)))
    })
  })
  await plugin.event(input)
  return received
}

try {
  const permission = await captureEvent({
    event: {
      type: "permission.asked",
      properties: {
        id: "permission-1",
        sessionID: "session-1",
        permission: "bash",
        patterns: ["pwd"],
        metadata: { tool: "bash" },
      },
    },
  })

  assert.equal(permission.session_id, "session-1")
  assert.equal(permission.status, "waiting_for_approval")
  assert.equal(permission.tool, "Bash")
  assert.equal(permission.tool_use_id, "permission-1")
  assert.deepEqual(permission.tool_input.patterns, ["pwd"])

  const failure = await captureEvent({
    event: {
      type: "session.error",
      properties: {
        sessionID: "session-1",
        error: { name: "APIError", data: { message: "Rate limited" } },
      },
    },
  })

  assert.equal(failure.status, "failed")
  assert.equal(failure.message, "Rate limited")
} finally {
  await new Promise((resolve) => server.close(resolve))
  await fs.rm(socketPath, { force: true })
}
