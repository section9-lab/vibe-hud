#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
chat_view="$repo_root/VibeHUD/UI/Views/ChatView.swift"
instances_view="$repo_root/VibeHUD/UI/Views/ClaudeInstancesView.swift"

if ! rg -Fq 'MessageItemView(item: item' "$chat_view"; then
    echo "Chat message rendering is missing"
    exit 1
fi

for forbidden in \
    'TextField(' \
    'sendInteractiveAnswer' \
    'ChatInteractivePromptBar' \
    'SessionAskUserQuestionCard'; do
    if rg -Fq -- "$forbidden" "$chat_view" "$instances_view"; then
        echo "Read-only chat still contains: $forbidden"
        exit 1
    fi
done

for removed_path in \
    "$repo_root/VibeHUD/Services/Reply" \
    "$repo_root/VibeHUD/Services/Chat/ClaudeInputBridgeClient.swift" \
    "$repo_root/VibeHUD/Services/Chat/TtyMessageSender.swift" \
    "$repo_root/VibeHUD/Resources/vibe-hud-bridge.py" \
    "$repo_root/VibeHUD/Resources/vibe-hud-tty-bridge.py"; do
    if [ -e "$removed_path" ]; then
        echo "Input-only path still exists: $removed_path"
        exit 1
    fi
done

if rg -n \
    'ReplyRouter|inputSocketPath|input_socket|VIBE_HUD_INPUT_SOCKET|ensure_tty_bridge' \
    "$repo_root/VibeHUD" \
    --glob '!Services/Hooks/HookInstaller.swift'; then
    echo "Input bridge references remain"
    exit 1
fi
