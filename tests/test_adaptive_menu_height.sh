#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
view_model="$repo_root/VibeHUD/Core/NotchViewModel.swift"
menu="$repo_root/VibeHUD/UI/Views/NotchMenuView.swift"

if rg -q 'height: 540' "$view_model"; then
    echo "The settings panel still uses a fixed 540-point height"
    exit 1
fi

if ! rg -q '@Published private\(set\) var menuContentHeight' "$view_model" ||
   ! rg -q 'func updateMenuContentHeight' "$view_model"; then
    echo "The view model does not track the settings content height"
    exit 1
fi

if ! rg -Uq 'case \.menu:[\s\S]{0,500}min\(windowHeight,[\s\S]{0,250}menuContentHeight' "$view_model"; then
    echo "The settings height is not derived from content and capped to the window"
    exit 1
fi

if ! rg -Fq 'MenuContentHeightPreferenceKey' "$menu" ||
   ! rg -Fq 'onPreferenceChange(MenuContentHeightPreferenceKey.self)' "$menu"; then
    echo "The settings view does not report its measured content height"
    exit 1
fi
