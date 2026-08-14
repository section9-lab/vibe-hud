#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/VibeHUD/Services/Hooks/HookInstaller.swift"

for requirement in \
    'getSessionId()' \
    'pid: process.pid' \
    'pi.on("session_shutdown"' \
    'pi.on("session_before_compact"' \
    'pi.on("session_compact"' \
    'event.willRetry ? "processing" : "waiting_for_input"' \
    'pi.on("tool_execution_start"' \
    'pi.on("tool_execution_end"' \
    'event.isError ? "PostToolUseFailure" : "PostToolUse"'; do
    if ! rg -Fq "$requirement" "$installer"; then
        echo "Pi hook lifecycle is missing: $requirement"
        exit 1
    fi
done
