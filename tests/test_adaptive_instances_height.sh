#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
view_model="$repo_root/VibeHUD/Core/NotchViewModel.swift"
instances_view="$repo_root/VibeHUD/UI/Views/ClaudeInstancesView.swift"

if rg -q 'height: 320' "$view_model"; then
    echo "The message panel still uses a fixed 320-point height"
    exit 1
fi

if ! rg -q '@Published private\(set\) var instancesContentHeight' "$view_model" ||
   ! rg -q 'func updateInstancesContentHeight' "$view_model"; then
    echo "The view model does not track message content height"
    exit 1
fi

if ! rg -Uq 'case \.instances:[\s\S]{0,300}min\(windowHeight,[\s\S]{0,200}instancesContentHeight' "$view_model"; then
    echo "The message panel height is not derived from its content"
    exit 1
fi

if ! rg -Fq 'InstancesContentHeightPreferenceKey' "$instances_view" ||
   ! rg -Fq 'onPreferenceChange(InstancesContentHeightPreferenceKey.self)' "$instances_view"; then
    echo "The message list does not report its measured height"
    exit 1
fi

if ! rg -q 'maximumVisibleSessionCount = 5' "$view_model" ||
   ! rg -Fq 'min(height, Self.maximumInstancesContentHeight)' "$view_model"; then
    echo "The message list is not capped to five visible sessions"
    exit 1
fi
