//
//  ClaudeInstancesView.swift
//  VibeHUD
//
//  Status-only session list. It never displays or opens conversation content.
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor

    var body: some View {
        VStack(spacing: 8) {
            if sessionMonitor.instances.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedInstances) { session in
                            InstanceRow(
                                session: session,
                                onFocus: { focusSession(session) },
                                onArchive: {
                                    sessionMonitor.archiveSession(sessionId: session.sessionId)
                                }
                            )
                            .id(session.stableId)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            Text("Run Claude Code, Codex, or OpenCode in Terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted {
            if priority($0.phase) != priority($1.phase) {
                return priority($0.phase) < priority($1.phase)
            }
            return $0.lastActivity > $1.lastActivity
        }
    }

    private func priority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .processing, .compacting: 0
        case .waitingForInput: 1
        case .idle, .ended: 2
        }
    }

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }
        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }
}

private struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onArchive: () -> Void

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false

    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(
        every: 0.15,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            stateIndicator
                .frame(width: 14)

            SessionSourceIcon(
                source: session.source,
                size: 12,
                animate: session.phase.isActive
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(SessionPhaseHelpers.phaseDescription(for: session.phase))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if session.isInTmux && isYabaiAvailable {
                statusButton(icon: "eye", action: onFocus)
            }
            if session.phase == .idle || session.phase == .waitingForInput {
                statusButton(icon: "archivebox", action: onArchive)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(sourceAccentColor)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

    private func statusButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sourceAccentColor: Color {
        switch session.source {
        case .claude:
            Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex:
            Color(red: 122 / 255, green: 157 / 255, blue: 1)
        case .opencode:
            .white
        }
    }
}
