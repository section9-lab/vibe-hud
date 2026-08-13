#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
icon="$repo_root/VibeHUD/AppIcon.icon/Assets/export-3.svg"

if rg -Fq 'data-lovart-layer-name="Vector 1"' "$icon"; then
    echo "The middle terminal icon is still present in the app icon"
    exit 1
fi

if rg -Fq '<image href=' "$icon"; then
    echo "The app icon still contains an internal symbol"
    exit 1
fi
