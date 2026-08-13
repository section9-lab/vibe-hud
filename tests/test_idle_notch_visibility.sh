#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
notch_view="$repo_root/VibeHUD/UI/Views/NotchView.swift"

if ! rg -q '@State private var isVisible: Bool = true' "$notch_view"; then
    echo "The closed notch is not visible by default"
    exit 1
fi

if rg -q 'isVisible = false' "$notch_view"; then
    echo "The closed notch is still hidden while idle"
    exit 1
fi

if ! rg -Uq 'private var showClosedActivity: Bool \{\n        true' "$notch_view"; then
    echo "The closed notch does not keep a persistent status icon"
    exit 1
fi

if rg -q 'ProcessingSpinner\(\)' "$notch_view"; then
    echo "The closed notch still renders a right-side processing spinner"
    exit 1
fi

if rg -q 'ReadyForInputIndicatorIcon' "$notch_view"; then
    echo "The closed notch still renders a right-side completion indicator"
    exit 1
fi

if ! rg -q 'private var closedNotchOffset: CGFloat' "$notch_view" ||
   ! rg -Fq '.offset(x: closedNotchOffset)' "$notch_view"; then
    echo "The closed notch is not anchored to the physical notch's right edge"
    exit 1
fi

if ! rg -Uq 'private var sideWidth: CGFloat \{\n        24' "$notch_view"; then
    echo "The closed notch's leading status area is wider than 24 points"
    exit 1
fi
