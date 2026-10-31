import SwiftUI

/// Silent until an update is available. One click consents to download,
/// verification, installation and relaunch; Sparkle remains responsible for each stage.
struct NotchUpdateButton: View {
    @ObservedObject var updateManager: UpdateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if updateManager.showsNotchIndicator {
            Button {
                updateManager.performPrimaryAction()
            } label: {
                Group {
                    if isBusy {
                        progressIndicator
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(TerminalColors.red)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(TerminalColors.red.opacity(isHovered && !isBusy ? 0.15 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isFocused ? TerminalColors.red : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .focusable(!isBusy)
            .focused($isFocused)
            .focusEffectDisabled()
            .onHover { isHovered = $0 }
            .help(helpText)
            .accessibilityLabel(title)
            .accessibilityHint(helpText)
            .accessibilityIdentifier("notch-update")
        }
    }

    private var isBusy: Bool {
        !updateManager.state.isInteractive
    }

    private var progress: Double? {
        switch updateManager.state {
        case .downloading(let progress), .extracting(let progress):
            return progress.isFinite ? min(max(progress, 0), 1) : 0
        default:
            return nil
        }
    }

    private var progressIndicator: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            ZStack {
                Circle().stroke(TerminalColors.red.opacity(0.2), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: max(progress ?? 0.25, 0.12))
                    .stroke(TerminalColors.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? -90 :
                        context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) * 300))
            }
            .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }

    private var title: String {
        switch updateManager.state {
        case .found, .readyToInstall:
            return "Update & Restart"
        case .downloading:
            return "Downloading \(Int((progress ?? 0) * 100))%"
        case .extracting:
            return "Preparing \(Int((progress ?? 0) * 100))%"
        case .installing:
            return "Restarting…"
        case .error:
            return "Retry Update"
        case .idle, .checking, .upToDate:
            return "Software Update"
        }
    }

    private var helpText: String {
        switch updateManager.state {
        case .found(let version, _), .readyToInstall(let version):
            return "Install v\(version) and restart vibe hud automatically."
        case .downloading, .extracting:
            return "\(title). vibe hud will install and restart automatically when ready."
        case .installing:
            return "Installing the update and restarting vibe hud."
        case .error(let message):
            return "\(message) Click to check for the update again."
        case .idle, .checking, .upToDate:
            return "Updates are checked automatically."
        }
    }
}
