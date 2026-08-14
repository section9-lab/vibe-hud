#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin="$repo_root/VibeHUD/Resources/vibe-hud.js"

for requirement in \
    'pid: process.pid' \
    'type === "session.status"' \
    'type === "session.error"' \
    'type === "permission.asked"' \
    'type === "permission.replied"' \
    'type === "question.asked"' \
    'type === "question.replied"' \
    'type === "question.rejected"'; do
    if ! rg -Fq "$requirement" "$plugin"; then
        echo "OpenCode lifecycle is missing: $requirement"
        exit 1
    fi
done

if rg -Uq 'type === "session\.created" \|\| type === "session\.updated"[\s\S]{0,500}waiting_for_input' "$plugin"; then
    echo "OpenCode session.updated still overwrites active status with waiting"
    exit 1
fi
