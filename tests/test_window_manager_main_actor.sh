#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
window_manager="$repo_root/VibeHUD/App/WindowManager.swift"
app_delegate="$repo_root/VibeHUD/App/AppDelegate.swift"

if ! rg -Uq '@MainActor\nclass WindowManager' "$window_manager"; then
    echo "WindowManager must be isolated to the main actor"
    exit 1
fi

if ! rg -Uq '@MainActor\n    var windowController' "$app_delegate" ||
   ! rg -Uq '@MainActor\n    private func handleScreenChange' "$app_delegate"; then
    echo "AppDelegate must access WindowManager on the main actor"
    exit 1
fi
