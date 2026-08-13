#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
store="$repo_root/VibeHUD/Services/State/SessionStore.swift"
monitor="$repo_root/VibeHUD/Services/Session/ClaudeSessionMonitor.swift"
phase="$repo_root/VibeHUD/Models/SessionPhase.swift"
recovery="$repo_root/VibeHUD/Services/Session/CodexSessionRecovery.swift"

if ! rg -Fq 'case (.idle, .waitingForInput):' "$phase"; then
    echo "A SessionStart event cannot become waiting for input"
    exit 1
fi

if [ ! -f "$recovery" ] ||
   ! rg -Fq 'CodexPaths.sessionsDir' "$recovery" ||
   ! rg -Fq 'recoverCodexSessions()' "$store"; then
    echo "Codex rollouts are not recovered after VibeHUD starts"
    exit 1
fi

if ! rg -Fq 'await SessionStore.shared.recoverCodexSessions()' "$monitor"; then
    echo "Codex rollout recovery is not started with monitoring"
    exit 1
fi
