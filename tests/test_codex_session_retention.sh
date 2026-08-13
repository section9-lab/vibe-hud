#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
store="$repo_root/VibeHUD/Services/State/SessionStore.swift"

if ! rg -Uq 'if session\.source != \.codex, let pid = session\.pid \{' "$store"; then
    echo "Codex sessions are still removed when their hook parent process exits"
    exit 1
fi
