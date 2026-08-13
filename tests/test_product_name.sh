#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plist="$repo_root/VibeHUD/Info.plist"
readme="$repo_root/README.md"
project="$repo_root/VibeHUD.xcodeproj/project.pbxproj"

if ! rg -Uq '<key>CFBundleDisplayName</key>\s*<string>vibe hud</string>' "$plist"; then
  echo "CFBundleDisplayName must be vibe hud" >&2
  exit 1
fi

if ! rg -Uq '<key>CFBundleName</key>\s*<string>vibe hud</string>' "$plist"; then
  echo "CFBundleName must be vibe hud" >&2
  exit 1
fi

if ! rg -Fq '<h1 align="center">vibe hud</h1>' "$readme"; then
  echo "README product title must be vibe hud" >&2
  exit 1
fi

if [ "$(rg -Fc 'PRODUCT_NAME = "vibe hud";' "$project" || true)" != "2" ]; then
  echo "Both app build configurations must produce vibe hud.app" >&2
  exit 1
fi
