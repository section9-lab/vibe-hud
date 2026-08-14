#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
store="$repo_root/VibeHUD/Services/State/SessionStore.swift"

if rg -Uq 'session\.source != \.codex' "$store" ||
   ! rg -Uq 'if let pid = session\.pid \{' "$store"; then
    echo "Codex sessions are excluded from normal process-liveness cleanup"
    exit 1
fi
