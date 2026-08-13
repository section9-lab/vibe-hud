#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
legacy_icon="$repo_root/VibeHUD/AppIcon.icon"

if [ -d "$legacy_icon" ]; then
    echo "The legacy AppIcon.icon source is still present"
    exit 1
fi
