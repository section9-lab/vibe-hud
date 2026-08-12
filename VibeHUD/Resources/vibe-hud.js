import net from "net"

const SOCKET_PATH = "/tmp/vibe-hud.sock"
let lastSequence = 0

function nextSequence() {
  lastSequence = Math.max(Date.now() * 1000, lastSequence + 1)
  return lastSequence
}

function sendEvent(event) {
  return new Promise((resolve) => {
    const client = net.createConnection(SOCKET_PATH)
    const finish = () => resolve()
    client.setTimeout(250)
    client.on("connect", () => {
      client.end(JSON.stringify({
        ...event,
        source: "opencode",
        event_sequence: nextSequence(),
      }))
    })
    client.on("close", finish)
    client.on("error", finish)
    client.on("timeout", () => {
      client.destroy()
      finish()
    })
  })
}

function baseState(sessionID, cwd) {
  return {
    session_id: sessionID || "unknown",
    cwd: cwd || process.cwd(),
  }
}

export default async function VibeHUDPlugin() {
  return {
    async event(input) {
      const event = input?.event
      const type = event?.type
      const props = event?.properties || {}
      if (!type) return

      if (type === "session.created") {
        await sendEvent({
          ...baseState(props.info?.id || props.sessionID, props.info?.directory),
          event: "SessionStart",
          status: "idle",
        })
      } else if (type === "session.updated" && props.info?.time?.archived) {
        await sendEvent({
          ...baseState(props.info?.id || props.sessionID, props.info?.directory),
          event: "SessionEnd",
          status: "ended",
        })
      } else if (type === "session.deleted") {
        await sendEvent({
          ...baseState(props.info?.id || props.sessionID, props.info?.directory),
          event: "SessionEnd",
          status: "ended",
        })
      } else if (type === "session.idle") {
        await sendEvent({
          ...baseState(props.sessionID, process.cwd()),
          event: "Stop",
          status: "waiting_for_input",
        })
      }
    },

    async "chat.message"(input) {
      await sendEvent({
        ...baseState(input.sessionID, process.cwd()),
        event: "UserPromptSubmit",
        status: "processing",
      })
    },

    async "tool.execute.before"(input) {
      await sendEvent({
        ...baseState(input.sessionID, process.cwd()),
        event: "PreToolUse",
        status: "processing",
      })
    },

    async "tool.execute.after"(input) {
      await sendEvent({
        ...baseState(input.sessionID, process.cwd()),
        event: "PostToolUse",
        status: "processing",
      })
    },
  }
}
