<div align="center">
  <img src="VibeHUD/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="vibe hud icon" width="120" height="120">
  <h1 align="center">vibe hud</h1>

  <p align="center">
    A native macOS notch HUD for Claude Code, Codex, and other AI coding agents. Follow sessions, read conversations, and review supported tool approvals from one place.
  </p>

[![GitHub Star](https://img.shields.io/github/stars/section9-lab/VibeHUD?style=rounded&color=white&labelColor=000000)](https://github.com/section9-lab/VibeHUD/stargazers)
[![GitHub license](https://img.shields.io/github/license/section9-lab/VibeHUD?style=rounded&color=white&labelColor=000000)](LICENSE)
[![Release Version](https://img.shields.io/github/v/release/section9-lab/VibeHUD?style=rounded&color=white&labelColor=000000)](https://github.com/section9-lab/VibeHUD/releases/latest)
![GitHub Repo size](https://img.shields.io/github/repo-size/section9-lab/VibeHUD?style=rounded&color=white&labelColor=000000&label=dmg%20size)

[![Kofi](https://img.shields.io/badge/Kofi-Jack-orange.svg?style=flat-square&logo=kofi)](https://ko-fi.com/jackvibe)
[![Patreon](https://img.shields.io/badge/Patreon-Jack-red.svg?style=flat-square&logo=patreon)](https://www.patreon.com/jack)

</div>

## Demo

<p align="center">
  <img src="docs/assets/vibe-hud-demo.gif?v=2" alt="Animated macOS notch demo showing agent rings, active session counts, menu bar app icons kept visible to the right of the hardware notch when the HUD is collapsed, and sessions from Claude Code, Codex, WorkBuddy, and Cursor" width="1000">
</p>
<p align="center"><sub>Simulated macOS desktop with sample sessions.</sub></p>

## What it does

vibe hud brings local AI coding sessions into your Mac’s notch. Follow Claude Code, Codex, and other supported agents while they continue to work in their own environments. The HUD shows session activity, conversation history, and tool content, and lets you approve or deny supported tool requests. Conversation content is read-only in the HUD; send messages, answer questions, and continue conversations in the original agent. Available approvals depend on the agent and its events.

[Website](https://hud.vibevibe.cc/) · [Download](https://hud.vibevibe.cc/download/) · [Setup guides](https://hud.vibevibe.cc/docs/) · [Compatibility](https://hud.vibevibe.cc/docs/compatibility/)

## Product highlights

- Monitor multiple Claude Code, Codex, and other supported agent sessions
- See session activity and open local conversation history in the HUD
- Review supported tool requests and approve or deny them from the notch
- Read conversation messages and tool content while continuing conversations in the original agent
- Enable integrations for Cursor, GitHub Copilot, Pi, OpenCode, and WorkBuddy from Agent Hooks
- Works with tmux, Terminal.app, iTerm2, and Ghostty
- Choose your display, sound, Claude directory, and startup behavior
- Built-in update checks and installs through Sparkle

## Main workflows

### Stay on top of active sessions

vibe hud follows supported Claude Code and Codex session events and keeps important state visible: running work, waiting input, tool requests, and recently active sessions.

### Handle approvals faster

When Claude needs permission to use a tool, vibe hud brings the approval flow to the notch so you can allow or deny it immediately.

### Know when a session needs attention

See when an agent is waiting for input or a tool approval. Handle supported approvals in the HUD, and return to the original agent to answer questions such as Claude's `AskUserQuestion` prompts or send a new message.

### Review conversations in one place

You can open a session view to see history, follow progress, and keep track of what Claude has been doing.

## Requirements

- macOS 15.6+
- A supported coding agent installed and configured, such as Claude Code or Codex

## Install

Download the latest release from the GitHub releases page and move `VibeHUD.app` into `/Applications`.

Open the notch menu, expand **Agent Hooks**, and enable the integration you use. Start a fresh agent session after enabling it. On subsequent launches, vibe hud refreshes hooks that were already enabled; installing the app alone does not enable every integration.

For Codex, run `/hooks` in Codex and review and trust the vibe hud hooks after enabling the integration or changing its hook definitions. The toggle registers the integration; Codex controls whether those hooks are trusted and allowed to run.

For setup and troubleshooting, see the [Claude Code guide](https://hud.vibevibe.cc/docs/claude-code/) and [Codex guide](https://hud.vibevibe.cc/docs/codex/).

Release downloads:
- https://github.com/section9-lab/VibeHUD/releases/latest

## Settings

From the notch menu, you can configure:

- preferred screen
- notification sound
- Claude config directory
- launch at login
- hooks on or off
- update checks and installs

## Compatibility

vibe hud monitors supported local agent sessions. Terminal detection and focusing depend on the environment, including:

- tmux
- Terminal.app
- iTerm2
- Ghostty
- accessibility fallback when needed

Available session details, approvals, and focusing features depend on the agent, emitted events, and your environment. Terminal focusing can benefit from tmux and optional window-management tooling. See the [agent and terminal compatibility guide](https://hud.vibevibe.cc/docs/compatibility/) for the current scope.

## Claude directory support

vibe hud works with the current Claude config layout and can resolve the config directory from:

1. `CLAUDE_CONFIG_DIR`
2. the directory you pick in vibe hud
3. `~/.config/claude`
4. `~/.claude`

## Updates

vibe hud checks for updates at launch and every hour through Sparkle. The update button sits directly to the left of Settings in the expanded HUD, including the session list and chat. When an update is available, it highlights **Update & Restart**; click once to download, install, and restart. Progress and retry status stay visible in the header and notch menu. The app only installs and restarts after you click.

GitHub tag releases require the `SPARKLE_PRIVATE_KEY` Actions secret matching `SUPublicEDKey` in `VibeHUD/Info.plist`. The workflow signs each DMG and verifies its signature against the built app's public key before publishing. Keep this key pair across releases.

Older builds without an update public key may need a one-time manual reinstall to establish trust in signed updates. Their in-app updater cannot accept a release that changes both the app signing identity and the update signing key.

## Privacy

The app reads local session events and conversation history to display the HUD. Anonymous Mixpanel analytics record app launches and the first actual HUD interaction on each reporting day, using a random installation identifier, app ID, app/build versions, and macOS version. Background agent activity does not count as HUD usage. Analytics do not include conversation text, agent session identifiers, project paths, commands, hardware UUIDs, or Claude Code versions; IP-based geolocation is disabled. Turn off **Share Anonymous Usage** in the notch menu to stop analytics. See the [privacy page](https://hud.vibevibe.cc/privacy/) for details.

### Shared app analytics

The public ingestion token in `VibeHUD/Info.plist` points to the owner's Mixpanel project. Forks should replace `MixpanelProjectToken` with their own project's token. No API secret or service-account credential belongs in the app.

Multiple apps can share this project by sending a different stable `app_id` on every event and using an app-specific random installation ID. All apps share the project's event allowance. See the [analytics setup guide](docs/analytics.md) for the event contract and dashboard configuration.

## Build from source

For a release-style local build:

```bash
./scripts/build.sh
```

To package a notarized release DMG:

```bash
./scripts/create-release.sh
```

## Tests

Run the native Swift test suite with Xcode:

```bash
xcodebuild test -project VibeHUD.xcodeproj -scheme VibeHUD -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The Python hook adapter, OpenCode JavaScript plugin, and release packaging contract retain focused runtime tests because those components execute outside the Swift process.

Run `bash tests/test_update_signature.sh` to verify acceptance of signed archives and rejection of modified archives, missing or mismatched keys, and incorrect release metadata.

## License

Apache 2.0
