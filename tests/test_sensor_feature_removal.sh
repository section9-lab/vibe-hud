#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d "$repo_root/SensorHelper" ]; then
    echo "SensorHelper directory is still present"
    exit 1
fi

if rg -n -i \
    -e 'SensorHelper' \
    -e 'SensorService' \
    -e 'SensorPrivileged' \
    -e 'AppleSPUAccelerometer' \
    -e 'vibrationTap' \
    -e 'singleTap' \
    -e 'doubleTap' \
    "$repo_root/VibeHUD" "$repo_root/VibeHUD.xcodeproj" "$repo_root/README.md"; then
    echo "Sensor feature references are still present"
    exit 1
fi
