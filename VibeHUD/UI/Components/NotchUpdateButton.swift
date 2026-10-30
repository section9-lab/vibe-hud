import SwiftUI

/// Keeps the updater accessible without leaving the session list or chat.
struct NotchUpdateButton: View {
    @ObservedObject var updateManager: UpdateManager
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            updateManager.performPrimaryAction()
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    if updateManager.state == .checking || updateManager.state == .installing {
                        progressIndicator
                    }
                    Text(title)
                }
                .fixedSize()

                compactLabel
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(isHovered && updateManager.state.isInteractive ? 0.2 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isFocused ? tint : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!updateManager.state.isInteractive)
        .focusable(updateManager.state.isInteractive)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(title)
        .accessibilityHint(helpText)
        .accessibilityIdentifier("notch-update")
    }

    private var progressIndicator: some View {
        ProgressView()
            .controlSize(.mini)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var compactLabel: some View {
        switch updateManager.state {
        case .idle:
            Text("Check")
        case .checking, .installing:
            progressIndicator
        case .upToDate:
            Text("Latest")
        case .found, .readyToInstall:
            Text("Update")
        case .downloading(let progress), .extracting(let progress):
            Text("\(Int(progress * 100))%")
        case .error:
            Text("Retry")
        }
    }

    private var title: String {
        switch updateManager.state {
        case .idle:
            return "Check for Updates"
        case .checking:
            return "Checking…"
        case .upToDate:
            return "Up to date"
        case .found, .readyToInstall:
            return "Update & Restart"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .extracting(let progress):
            return "Preparing \(Int(progress * 100))%"
        case .installing:
            return "Restarting…"
        case .error:
            return "Retry Update"
        }
    }

    private var tint: Color {
        switch updateManager.state {
        case .idle, .checking:
            return .white.opacity(isHovered ? 1 : 0.7)
        case .upToDate, .found, .readyToInstall:
            return TerminalColors.green
        case .downloading, .installing:
            return TerminalColors.blue
        case .extracting:
            return TerminalColors.amber
        case .error:
            return TerminalColors.red
        }
    }

    private var helpText: String {
        switch updateManager.state {
        case .idle:
            return "Updates are checked automatically. Click to check now."
        case .checking:
            return "Checking for updates."
        case .upToDate:
            return "You're using the latest version. Click to check again."
        case .found(let version, _), .readyToInstall(let version):
            return "Install v\(version) and restart vibe hud."
        case .downloading, .extracting:
            return "The update will install and restart vibe hud when ready."
        case .installing:
            return "Installing the update and restarting vibe hud."
        case .error(let message):
            return "\(message) Click to retry."
        }
    }
}
