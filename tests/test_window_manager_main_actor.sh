#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
window_manager="$repo_root/VibeHUD/App/WindowManager.swift"

if ! rg -Uq '@MainActor\nclass WindowManager' "$window_manager"; then
    echo "WindowManager must be isolated to the main actor"
    exit 1
fi
