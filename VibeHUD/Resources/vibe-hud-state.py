#!/usr/bin/env python3
"""Send lifecycle-only state to VibeHUD without collecting conversation data."""

import json
import os
import socket
import subprocess
import sys
import time

SOCKET_PATH = "/tmp/vibe-hud.sock"
VALID_SOURCES = {"claude", "codex", "opencode"}


def source_from_args(data):
    args = sys.argv[1:]
    for index, arg in enumerate(args):
        if arg == "--source" and index + 1 < len(args):
            value = args[index + 1].strip().lower()
            return value if value in VALID_SOURCES else "claude"
        if arg.startswith("--source="):
            value = arg.split("=", 1)[1].strip().lower()
            return value if value in VALID_SOURCES else "claude"
    value = str(data.get("source", "claude")).strip().lower()
    return value if value in VALID_SOURCES else "claude"


def process_value(pid, field):
    try:
        result = subprocess.run(
            ["ps", "-p", str(pid), "-o", f"{field}="],
            capture_output=True,
            text=True,
            timeout=0.5,
        )
        value = result.stdout.strip()
        return value or None
    except Exception:
        return None


def parent_pid(pid):
    value = process_value(pid, "ppid")
    try:
        return int(value) if value else None
    except ValueError:
        return None


def terminal_metadata(start_pid):
    known = {
        "terminal": "com.apple.Terminal",
        "iterm": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "warp": "dev.warp.Warp-Stable",
        "wezterm": "com.github.wez.wezterm",
        "alacritty": "io.alacritty",
        "kitty": "net.kovidgoyal.kitty",
    }
    pid = start_pid
    for _ in range(16):
        command = (process_value(pid, "comm") or "").lower()
        for name, bundle_id in known.items():
            if name in command:
                return pid, bundle_id
        pid = parent_pid(pid)
        if not pid or pid <= 1:
            break
    return None, None


def tty_for_process(pid):
    value = process_value(pid, "tty")
    if not value or value in {"??", "-"}:
        return None
    return value if value.startswith("/dev/") else f"/dev/{value}"


def status_for(data):
    event = data.get("hook_event_name", "")
    if event == "SessionStart":
        return "idle"
    if event in {
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "SubagentStart",
        "SubagentStop",
        "PostCompact",
    }:
        return "processing"
    if event == "PreCompact":
        return "compacting"
    if event in {"Stop", "StopFailure"}:
        return "waiting_for_input"
    if event == "SessionEnd":
        return "ended"
    if event == "Notification" and data.get("notification_type") == "idle_prompt":
        return "waiting_for_input"
    return None


def send_event(event):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(0.25)
            client.connect(SOCKET_PATH)
            client.sendall(json.dumps(event, separators=(",", ":")).encode())
    except (OSError, TypeError, ValueError):
        pass


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        return 1

    status = status_for(data)
    if status is None:
        return 0

    agent_pid = os.getppid()
    terminal_pid, terminal_bundle_id = terminal_metadata(agent_pid)
    tmux = os.environ.get("TMUX", "")
    event = {
        "session_id": data.get("session_id", "unknown"),
        "cwd": data.get("cwd", ""),
        "event": data.get("hook_event_name", ""),
        "status": status,
        "source": source_from_args(data),
        "pid": agent_pid,
        "tty": tty_for_process(agent_pid),
        "terminal_pid": terminal_pid,
        "terminal_bundle_id": terminal_bundle_id,
        "tmux_pane": os.environ.get("TMUX_PANE"),
        "tmux_socket": tmux.split(",", 1)[0] if tmux else None,
        "event_sequence": time.time_ns(),
        "notification_type": data.get("notification_type"),
    }
    send_event(event)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
