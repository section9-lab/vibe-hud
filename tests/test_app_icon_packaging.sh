#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
iconset="$repo_root/VibeHUD/Assets.xcassets/AppIcon.appiconset"
contents="$iconset/Contents.json"
workflow="$repo_root/.github/workflows/release.yml"

if [ ! -f "$contents" ] || [ "$(rg -c '"filename"' "$contents")" -ne 10 ]; then
    echo "The standard macOS AppIcon set is incomplete"
    exit 1
fi

if [ -d "$repo_root/VibeHUD/AppIcon.icon" ]; then
    echo "The unsupported AppIcon.icon source must not be packaged"
    exit 1
fi

if ! rg -Fq 'vibe hud.app' "$workflow"; then
    echo "Release workflow does not package the renamed app bundle"
    exit 1
fi
