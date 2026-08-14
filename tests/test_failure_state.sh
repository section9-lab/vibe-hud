#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
phase="$repo_root/VibeHUD/Models/SessionPhase.swift"
event="$repo_root/VibeHUD/Models/SessionEvent.swift"
instances="$repo_root/VibeHUD/UI/Views/ClaudeInstancesView.swift"
store="$repo_root/VibeHUD/Services/State/SessionStore.swift"
monitor="$repo_root/VibeHUD/Services/Session/ClaudeSessionMonitor.swift"

if ! rg -Fq 'case failed(String?)' "$phase" ||
   ! rg -Uq 'case "failed":[\n ]+return \.failed\(message\)' "$event"; then
    echo "Terminal agent failures are still represented as successful completion"
    exit 1
fi

if ! rg -Fq 'if event.event == "PostToolUse" || event.event == "PostToolUseFailure"' "$monitor"; then
    echo "Failed tools leave permission sockets pending"
    exit 1
fi

if ! rg -Uq 'case "PostToolUse", "PostToolUseFailure":[\s\S]{0,900}tool\.status = success \? \.success : \.error' "$store"; then
    echo "Failed tool calls remain marked as running"
    exit 1
fi

if ! rg -Fq 'event == "PostToolUseFailure"' "$event" ||
   ! rg -Fq 'case "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure":' "$event"; then
    echo "Failure hooks do not participate in tool handling and transcript synchronization"
    exit 1
fi

if ! rg -Uq 'case \.failed:[\s\S]{0,120}TerminalColors\.red' "$instances"; then
    echo "Failed sessions are not visually distinguished from ready sessions"
    exit 1
fi
