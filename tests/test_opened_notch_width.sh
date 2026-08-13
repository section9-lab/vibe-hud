#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
view_model="$repo_root/VibeHUD/Core/NotchViewModel.swift"

if ! rg -Uq 'case \.chat:[\s\S]{0,200}width: min\(screenRect\.width \* 0\.4, 480\)' "$view_model"; then
    echo "The chat panel width has not been reduced by one fifth"
    exit 1
fi

if [ "$(rg -F 'width: min(screenRect.width * 0.32, 384)' "$view_model" | wc -l | tr -d ' ')" != "2" ]; then
    echo "The menu and instances panel widths have not been reduced by one fifth"
    exit 1
fi
