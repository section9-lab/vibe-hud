#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
event_model="$repo_root/VibeHUD/Models/SessionEvent.swift"

if ! rg -Uq 'case "waiting_for_approval":[\n ]+return \.waitingForApproval' "$event_model"; then
    echo "Non-blocking approval events cannot enter waiting-for-approval state"
    exit 1
fi
