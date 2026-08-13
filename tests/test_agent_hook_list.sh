#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/VibeHUD/Services/Hooks/HookInstaller.swift"
menu="$repo_root/VibeHUD/UI/Views/NotchMenuView.swift"
view_model="$repo_root/VibeHUD/Core/NotchViewModel.swift"

for agent in claude codex cursor githubCopilot pi openCode; do
    if ! rg -q "case $agent" "$installer"; then
        echo "Missing independent hook definition for $agent"
        exit 1
    fi
done

if ! rg -Fq 'viewModel.hookListExpanded = isHooksExpanded' "$menu" ||
   ! rg -Fq 'onPreferenceChange(MenuContentHeightPreferenceKey.self)' "$menu"; then
    echo "The menu does not resize when the Agent Hooks list expands"
    exit 1
fi

if rg -q 'label: "Hooks"' "$menu"; then
    echo "The settings menu still exposes the single global Hooks switch"
    exit 1
fi

for label in Claude Codex Cursor "GitHub Copilot" Pi OpenCode; do
    if ! rg -Fq "label: \"$label\"" "$menu"; then
        echo "Missing $label hook toggle in the settings menu"
        exit 1
    fi
done

if [ "$(rg -F 'isNested: true' "$menu" | wc -l | tr -d ' ')" != "6" ]; then
    echo "Every Agent Hook child row must be indented"
    exit 1
fi

if ! rg -q 'let isNested: Bool' "$menu" ||
   ! rg -Fq '.padding(.leading, isNested ? 16 : 0)' "$menu"; then
    echo "The hook child indentation is not implemented by the toggle row"
    exit 1
fi

if ! rg -q '@State private var isHooksExpanded: Bool = false' "$menu" ||
   ! rg -q 'if isHooksExpanded' "$menu"; then
    echo "The Agent Hooks list is not collapsed by default"
    exit 1
fi

if ! rg -Uq 'func toggleMenu\(\) \{\n        if contentType == \.menu \{\n            hookListExpanded = false' "$view_model"; then
    echo "The Agent Hooks list stays expanded after leaving settings"
    exit 1
fi

if ! rg -Fq 'command: "python3 \(shellQuote(CursorPaths.hookScriptPath.path)) --source cursor"' "$installer" ||
   ! rg -Fq 'command: "python3 \(shellQuote(CopilotPaths.hookScriptPath.path)) --source copilot"' "$installer"; then
    echo "Cursor or Copilot hook command does not interpolate the script path"
    exit 1
fi

if ! rg -q 'isManagedCommandHook' "$installer"; then
    echo "Legacy invalid hook commands are not cleaned up"
    exit 1
fi

if ! rg -Uq 'case \.codex:\n            removeHooks\(at: CodexPaths\.hooksFile\)' "$installer" ||
   rg -Uq 'case \.codex:[\s\S]{0,180}removeItem\(at: CodexPaths\.hookScriptPath\)' "$installer"; then
    echo "Codex uninstall does not preserve the script for already-running sessions"
    exit 1
fi
