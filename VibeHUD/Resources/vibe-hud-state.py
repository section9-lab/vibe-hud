#!/usr/bin/env python3
"""
VibeHUD Hook
- Sends session state to VibeHUD.app via Unix socket
- For Claude PermissionRequest: waits for user decision from the app
"""
import json
import os
import socket
import subprocess
import sys
import time

SOCKET_PATH = "/tmp/vibe-hud.sock"
TIMEOUT_SECONDS = 300  # 5 minutes for permission decisions
VALID_SOURCES = {"claude", "codex", "cursor", "copilot", "vscodeagent", "pi", "opencode", "workbuddy"}

EVENT_ALIASES = {
    "sessionStart": "SessionStart",
    "sessionEnd": "SessionEnd",
    "beforeSubmitPrompt": "UserPromptSubmit",
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "postToolUseFailure": "PostToolUseFailure",
    "permissionRequest": "PermissionRequest",
    "agentStop": "Stop",
    "stop": "Stop",
    "afterAgentResponse": "Stop",
    "userPromptSubmitted": "UserPromptSubmit",
    "errorOccurred": "StopFailure",
    "notification": "Notification",
    "preCompact": "PreCompact",
    "postCompact": "PostCompact",
    "subagentStart": "SubagentStart",
    "subagentStop": "SubagentStop",
    "Error": "StopFailure",
}


def parse_source_arg():
    """Read an explicit source from the hook command, matching Vibe Island's approach."""
    for index, arg in enumerate(sys.argv[1:]):
        if arg == "--source" and index + 2 <= len(sys.argv[1:]):
            source = sys.argv[index + 2].strip().lower()
            return source if source in VALID_SOURCES else None
        if arg.startswith("--source="):
            source = arg.split("=", 1)[1].strip().lower()
            return source if source in VALID_SOURCES else None
    return None


def parse_event_arg():
    """Read an explicit event name when the client payload omits one."""
    arguments = sys.argv[1:]
    for index, arg in enumerate(arguments):
        if arg == "--event" and index + 1 < len(arguments):
            return arguments[index + 1]
        if arg.startswith("--event="):
            return arg.split("=", 1)[1]
    return None


def infer_source(data):
    """Best-effort fallback for older installed hooks that do not pass --source."""
    explicit = data.get("source")
    if isinstance(explicit, str) and explicit.strip().lower() in VALID_SOURCES:
        return explicit.strip().lower()

    if data.get("hook_event_name") in {"PreCompact", "PostCompact", "PermissionRequest", "Notification"}:
        return "claude"

    transcript_path = data.get("transcript_path")
    if isinstance(transcript_path, str):
        lower_path = transcript_path.lower()
        if "/.codex/" in lower_path:
            return "codex"
        if "/.claude/" in lower_path or "/.config/claude/" in lower_path:
            return "claude"

    return "claude"


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    # Get parent PID (Claude process)
    ppid = os.getppid()

    # Try to get TTY from ps command for the parent process
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps returns just "ttys001", we need "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # Fallback: try current process stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def get_process_command(pid):
    """Get process command name for a pid."""
    try:
        result = subprocess.run(
            ["ps", "-p", str(pid), "-o", "comm="],
            capture_output=True,
            text=True,
            timeout=2
        )
        cmd = result.stdout.strip()
        return cmd if cmd else None
    except Exception:
        return None


def find_agent_pid(source, start_pid):
    """Find the durable agent process instead of retaining a transient hook shell."""
    patterns = {
        "claude": ("/claude", "claude.app"),
        "codex": ("/codex", "codex.app"),
        "cursor": ("/cursor", "cursor.app"),
        "copilot": ("/copilot", "github-copilot"),
        "vscodeagent": ("visual studio code", "code helper"),
        "workbuddy": ("/workbuddy", "workbuddy.app", "/codebuddy"),
    }.get(source, ())

    current = start_pid
    for _ in range(20):
        try:
            result = subprocess.run(
                ["ps", "-p", str(current), "-o", "ppid=,command="],
                capture_output=True,
                text=True,
                timeout=2,
            )
            line = result.stdout.strip()
            if not line:
                return None
            ppid_text, command = line.split(None, 1)
            command_without_hook_args = command.lower().split(" --source ", 1)[0]
            if any(pattern in command_without_hook_args for pattern in patterns):
                return current

            ppid = int(ppid_text)
            if ppid <= 1:
                return None
            current = ppid
        except Exception:
            return None

    return None


def find_terminal_pid(start_pid):
    """Walk parent chain to find a known terminal process pid."""
    known = [
        "Terminal", "iTerm", "iTerm2", "Ghostty", "Warp",
        "Alacritty", "kitty", "WezTerm", "Hyper", "Tabby"
    ]

    current = start_pid
    for _ in range(20):
        try:
            result = subprocess.run(
                ["ps", "-p", str(current), "-o", "ppid=,comm="],
                capture_output=True,
                text=True,
                timeout=2
            )
            line = result.stdout.strip()
            if not line:
                return None
            parts = line.split(None, 1)
            if len(parts) < 2:
                return None
            ppid = int(parts[0])
            comm = parts[1]

            if any(name.lower() in comm.lower() for name in known):
                return current

            if ppid <= 1:
                return None
            current = ppid
        except Exception:
            return None

    return None


def map_bundle_id(command):
    """Best-effort mapping from process command to terminal bundle ID."""
    if not command:
        return None

    c = command.lower()
    if "iterm" in c:
        return "com.googlecode.iterm2"
    if c.endswith("/terminal") or c == "terminal":
        return "com.apple.Terminal"
    if "ghostty" in c:
        return "com.mitchellh.ghostty"
    if "warp" in c:
        return "dev.warp.Warp-Stable"
    if "wezterm" in c:
        return "com.github.wez.wezterm"
    if "alacritty" in c:
        return "io.alacritty"
    if "kitty" in c:
        return "net.kovidgoyal.kitty"
    if "hyper" in c:
        return "co.zeit.hyper"
    return None


def send_event(state):
    """Send event to app, return response if any"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        # For permission requests, wait for response
        if state.get("status") == "waiting_for_approval":
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    source = parse_source_arg() or infer_source(data)
    session_id = (
        data.get("session_id")
        or data.get("sessionId")
        or data.get("conversation_id")
        or data.get("conversationId")
        or "unknown"
    )
    if source == "vscodeagent" and not str(session_id).startswith("vscodeagent-"):
        session_id = f"vscodeagent-{session_id}"
    raw_event = parse_event_arg() or data.get("hook_event_name") or data.get("hookEventName") or ""
    event = EVENT_ALIASES.get(raw_event, raw_event)
    cwd = data.get("cwd") or next(iter(data.get("workspace_roots", [])), "")
    tool_name = data.get("tool_name") or data.get("toolName")
    tool_input = data.get("tool_input") or data.get("toolArgs") or data.get("toolInput") or {}
    tool_use_id = data.get("tool_use_id") or data.get("toolCallId") or data.get("toolUseId")

    # Get process info
    hook_parent_pid = os.getppid()
    agent_pid = find_agent_pid(source, hook_parent_pid)
    tty = get_tty()
    terminal_pid = find_terminal_pid(hook_parent_pid)
    terminal_cmd = get_process_command(terminal_pid) if terminal_pid else None
    terminal_bundle_id = map_bundle_id(terminal_cmd)

    tmux_env = os.environ.get("TMUX", "")
    tmux_socket = tmux_env.split(",")[0] if tmux_env else None
    source_timestamp = data.get("event_timestamp") or data.get("timestamp")
    if not isinstance(source_timestamp, (int, float)):
        source_timestamp = time.time()

    # Build state object
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "source": source,
        "pid": agent_pid,
        "tty": tty,
        "transcript_path": data.get("transcript_path"),
        "terminal_pid": terminal_pid,
        "terminal_bundle_id": terminal_bundle_id,
        "tmux_pane": os.environ.get("TMUX_PANE"),
        "tmux_socket": tmux_socket,
        "event_id": data.get("hook_event_id") or data.get("hookEventId"),
        "event_timestamp": float(source_timestamp),
    }

    # Map events to status
    if event == "UserPromptSubmit":
        # User just sent a message - Claude is now processing
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        # Send tool_use_id to Swift for caching
        if tool_use_id:
            state["tool_use_id"] = tool_use_id

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        # Send tool_use_id so Swift can cancel the specific pending permission
        if tool_use_id:
            state["tool_use_id"] = tool_use_id

    elif event == "PostToolUseFailure":
        # Tool errored or was interrupted — main session continues processing
        state["status"] = "processing"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        state["tool_error"] = data.get("error") or data.get("message")
        if tool_use_id:
            state["tool_use_id"] = tool_use_id

    elif event == "PermissionDenied":
        # Auto-mode classifier denied a tool call — surface to the app so the
        # user can see what was blocked instead of a silent skip
        state["status"] = "processing"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        state["denial_reason"] = data.get("reason") or data.get("message")

    elif event == "PermissionRequest":
        # This is where we can control the permission
        state["status"] = "waiting_for_approval"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        # tool_use_id lookup handled by Swift-side cache from PreToolUse

        # Send to app and wait for decision
        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                # Output JSON to approve
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                # Output JSON to deny
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via VibeHUD",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        # No response or "ask" - let Claude Code show its normal UI
        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type") or data.get("notificationType")
        # Skip permission_prompt - PermissionRequest hook handles this with better info
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type in {"idle_prompt", "agent_needs_input", "agent_completed"}:
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        if data.get("status") in {"error", "failed", "failure"}:
            state["status"] = "failed"
            state["message"] = data.get("error") or data.get("message")
        else:
            state["status"] = "waiting_for_input"

    elif event == "StopFailure":
        state["status"] = "failed"
        state["message"] = data.get("error") or data.get("message")

    elif event == "SubagentStart":
        # A subagent task is beginning — main session is still processing
        state["status"] = "processing"

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - main session continues processing
        state["status"] = "processing"

    elif event == "SessionStart":
        # New session starts waiting for user input
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        # Context is being compacted (manual or auto)
        state["status"] = "compacting"

    elif event == "PostCompact":
        # Compaction finished — return to processing so UI exits .compacting phase
        state["status"] = "processing"

    elif event == "Elicitation":
        state["status"] = "waiting_for_input"

    elif event in {"ElicitationResult", "TeammateIdle", "TaskCreated", "TaskCompleted"}:
        state["status"] = "processing"

    else:
        state["status"] = "unknown"

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
