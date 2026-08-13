#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$repo_root/.github/workflows/release.yml"

if [ ! -f "$workflow" ]; then
    echo "Missing the release tag workflow"
    exit 1
fi

if ! rg -Fq '  push:' "$workflow" ||
   ! rg -Fq '    tags:' "$workflow" ||
   ! rg -Fq '      - "v*"' "$workflow"; then
    echo "Release workflow is not triggered by v* tags"
    exit 1
fi

for required in \
    'contents: write' \
    'runs-on: macos-15' \
    'CODE_SIGNING_ALLOWED=NO' \
    'hdiutil create' \
    'softprops/action-gh-release@v2'; do
    if ! rg -Fq "$required" "$workflow"; then
        echo "Release workflow is missing: $required"
        exit 1
    fi
done

if ! rg -Fq 'github.ref_name' "$workflow"; then
    echo "Release asset name is not tied to the pushed tag"
    exit 1
fi
