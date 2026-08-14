#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook_event="$repo_root/VibeHUD/Services/Hooks/HookSocketServer.swift"
session_state="$repo_root/VibeHUD/Models/SessionState.swift"
store="$repo_root/VibeHUD/Services/State/SessionStore.swift"

for field in eventId eventTimestamp; do
    if ! rg -Fq "let $field:" "$hook_event"; then
        echo "Hook event is missing ordering field: $field"
        exit 1
    fi
done

if ! rg -Fq 'var lastEventTimestamp: TimeInterval?' "$session_state"; then
    echo "Session state does not retain the latest source event timestamp"
    exit 1
fi

if ! rg -Fq 'processedHookEventIds.contains(eventKey)' "$store" ||
   ! rg -Fq 'eventTimestamp < lastEventTimestamp' "$store"; then
    echo "Duplicate or out-of-order hook events can still overwrite current state"
    exit 1
fi
