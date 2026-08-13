#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if rg -q 'ClaudeDirPickerRow|ClaudeDirSelector|claudeDirSelector|claudeDirectoryName' "$repo_root/VibeHUD" --glob '*.swift'; then
    echo "The Claude-specific directory setting is still present"
    exit 1
fi

for file in \
    "$repo_root/VibeHUD/Core/ClaudeDirSelector.swift" \
    "$repo_root/VibeHUD/UI/Components/ClaudeDirPickerRow.swift"; do
    if [ -e "$file" ]; then
        echo "Obsolete settings file remains: $file"
        exit 1
    fi
done
