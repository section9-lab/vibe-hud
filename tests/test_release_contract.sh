#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$repo_root/.github/workflows/release.yml"
plist="$repo_root/VibeHUD/Info.plist"
project="$repo_root/VibeHUD.xcodeproj/project.pbxproj"
icon_contents="$repo_root/VibeHUD/Assets.xcassets/AppIcon.appiconset/Contents.json"

for required in \
    '      - "v*"' \
    'contents: write' \
    'runs-on: macos-15' \
    'xcodebuild test' \
    'python3 -m unittest tests/test_hook_state_adapter.py -v' \
    'node tests/test_opencode_plugin.mjs' \
    'CODE_SIGNING_ALLOWED=NO' \
    'codesign --force --deep --sign -' \
    'codesign --verify --deep --strict' \
    'ln -s /Applications' \
    'hdiutil create' \
    'softprops/action-gh-release@v2'; do
    if ! grep -Fq -- "$required" "$workflow"; then
        echo "Release workflow is missing: $required" >&2
        exit 1
    fi
done

for key in CFBundleDisplayName CFBundleName; do
    if [ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")" != "vibe hud" ]; then
        echo "$key must be vibe hud" >&2
        exit 1
    fi
done

if [ "$(grep -Fc 'PRODUCT_NAME = "vibe hud";' "$project")" -ne 2 ]; then
    echo "Both app configurations must produce vibe hud.app" >&2
    exit 1
fi

if [ "$(grep -c '"filename"' "$icon_contents")" -ne 10 ]; then
    echo "The standard macOS icon set is incomplete" >&2
    exit 1
fi

if [ -d "$repo_root/VibeHUD/AppIcon.icon" ]; then
    echo "The unsupported AppIcon.icon source must not be packaged" >&2
    exit 1
fi
