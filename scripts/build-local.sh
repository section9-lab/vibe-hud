#!/bin/bash
# Build a self-contained local app from this checkout. Xcode builds Assets.car;
# Command Line Tools use the catalog's source icons as PNG resources.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build-local"
mkdir -p "$BUILD_DIR"
STAGE="$(mktemp -d "$BUILD_DIR/.stage.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/VibeHUDLocal.app"
RESOURCES="$APP/Contents/Resources"
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$RESOURCES" "$FRAMEWORKS" "$APP/Contents/MacOS"

if xcrun --find xcodebuild >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
    xcodebuild build -project "$PROJECT_DIR/VibeHUD.xcodeproj" -scheme VibeHUD \
        -configuration Debug -destination 'platform=macOS' \
        -derivedDataPath "$BUILD_DIR/DerivedData" CODE_SIGNING_ALLOWED=NO \
        PRODUCT_BUNDLE_IDENTIFIER="${VIBE_HUD_LOCAL_BUNDLE_ID:-com.example.VibeHUDLocal}"
    ditto "$BUILD_DIR/DerivedData/Build/Products/Debug/vibe hud.app" "$APP"
    RESOURCES="$APP/Contents/Resources"
else
    cd "$PROJECT_DIR"
    swift build -j 2 -c debug --product VibeHUDLocal
    BIN_DIR="$(swift build -c debug --show-bin-path)"
    ditto "$BIN_DIR/VibeHUDLocal" "$APP/Contents/MacOS/vibe hud"
    ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
    ditto "$BIN_DIR/VibeHUDLocal_VibeHUDLocal.bundle" "$RESOURCES/VibeHUDLocal_VibeHUDLocal.bundle"
    for set in "$PROJECT_DIR"/VibeHUD/Assets.xcassets/Agent*.imageset; do
        name="$(basename "$set" .imageset)"
        source="$(find "$set" -maxdepth 1 -type f \( -name '*.svg' -o -name '*.png' \) -print -quit)"
        if [[ -n "$source" ]]; then sips -s format png "$source" --out "$RESOURCES/$name.png" >/dev/null; fi
    done
    iconset="$STAGE/AppIcon.iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        cp "$PROJECT_DIR/VibeHUD/Assets.xcassets/AppIcon.appiconset/icon_${size}x${size}.png" \
            "$iconset/icon_${size}x${size}.png"
        cp "$PROJECT_DIR/VibeHUD/Assets.xcassets/AppIcon.appiconset/icon_${size}x${size}@2x.png" \
            "$iconset/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$iconset" -o "$RESOURCES/AppIcon.icns"
    if ! otool -l "$APP/Contents/MacOS/vibe hud" | grep -F '@executable_path/../Frameworks' >/dev/null; then
        install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/vibe hud"
    fi
fi

for resource in vibe-hud-state.py vibe-hud.js LobeIcons-LICENSE.txt \
                codex_usage.py codex_speed.py tibo_reset.py claude_statusline.py claude_speed.py; do
    ditto "$PROJECT_DIR/VibeHUD/Resources/$resource" "$RESOURCES/$resource"
done
ditto "$PROJECT_DIR/LICENSE" "$RESOURCES/VibeHUD-LICENSE"
ditto "$PROJECT_DIR/LICENSE.md" "$RESOURCES/VibeHUD-LICENSE.md"
ditto "$PROJECT_DIR/VibeHUD/Resources/usage-workers-LICENSE.txt" "$RESOURCES/usage-workers-LICENSE.txt"

python3 - "$PROJECT_DIR/VibeHUD/Info.plist" "$PROJECT_DIR/VibeHUD.xcodeproj/project.pbxproj" "$APP/Contents/Info.plist" <<'PY'
import os
import plistlib
import re
import sys
from pathlib import Path

source, project, destination = map(Path, sys.argv[1:])
project_text = project.read_text()

def project_setting(name):
    values = set(re.findall(rf'\b{name}\s*=\s*([\w.]+)\s*;', project_text))
    if len(values) != 1:
        raise ValueError(f'Expected one {name} value in {project}: {values}')
    return values.pop()

if destination.exists():
    with destination.open('rb') as stream:
        info = plistlib.load(stream)
else:
    with source.open('rb') as stream:
        info = plistlib.load(stream)
info.update(CFBundleIdentifier=os.environ.get('VIBE_HUD_LOCAL_BUNDLE_ID', 'com.example.VibeHUDLocal'),
            CFBundleExecutable='vibe hud',
            CFBundleName=os.environ.get('VIBE_HUD_LOCAL_NAME', 'Vibe HUD Local'),
            CFBundleDisplayName=os.environ.get('VIBE_HUD_LOCAL_NAME', 'Vibe HUD Local'),
            CFBundleIconFile='AppIcon', CFBundlePackageType='APPL',
            CFBundleVersion=project_setting('CURRENT_PROJECT_VERSION'),
            CFBundleShortVersionString=project_setting('MARKETING_VERSION'),
            LSMinimumSystemVersion='15.6', VibeHUDLocalBuild=True,
            VibeHUDRequiresTakeover=os.environ.get('VIBE_HUD_REQUIRE_TAKEOVER') == '1',
            SUEnableAutomaticChecks=False)
info.pop('SUFeedURL', None)
info.pop('SUPublicEDKey', None)
if os.environ.get('VIBE_HUD_LOCAL_CACHE_DIR'):
    info['VibeHUDMonitoringCachePath'] = os.environ['VIBE_HUD_LOCAL_CACHE_DIR']
with destination.open('wb') as stream:
    plistlib.dump(info, stream)
PY

SIGN_IDENTITY="${VIBE_HUD_LOCAL_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
rm -rf "$BUILD_DIR/VibeHUDLocal.app"
mv "$APP" "$BUILD_DIR/VibeHUDLocal.app"
echo "$BUILD_DIR/VibeHUDLocal.app"
