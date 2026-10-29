//
//  NotchMenuView.swift
//  VibeHUD
//
//  Minimal menu matching Dynamic Island aesthetic
//

import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

// MARK: - NotchMenuView

private struct MenuContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var soundSelector = SoundSelector.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var hookStates: [HookAgent: Bool] = [:]
    @State private var isHooksExpanded: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var expandedSection: MenuSection?
    @State private var loginError: String?
    @State private var hookError: String?
    @State private var linkError: String?

    private enum MenuSection: Equatable { case language, display, tibo }

    private func tr(_ key: String) -> String {
        AppLocalization.string(key, language: preferences.language)
    }

    var body: some View {
        // ScrollView so the menu gracefully scrolls when content exceeds the
        // panel height (e.g. both picker rows expanded on a small panel).
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                // Back button
                MenuRow(
                    icon: "chevron.left",
                    label: tr("menu.back")
                ) {
                    viewModel.toggleMenu()
                }

                if AppRuntime.isPreview {
                    Text(tr("menu.previewNotice"))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                ScreenPickerRow(screenSelector: screenSelector)
                SoundPickerRow(soundSelector: soundSelector)

                sectionRow(.language, icon: "globe", label: tr("menu.language"), detail: preferences.language.displayName)
                if expandedSection == .language {
                    ForEach(AppLanguage.allCases) { language in
                        MenuToggleRow(icon: "character.bubble", label: language.displayName,
                                      isOn: preferences.language == language, isNested: true) {
                            preferences.language = language
                        }
                    }
                }

                sectionRow(.display, icon: "eye", label: tr("menu.display"))
                if expandedSection == .display {
                    ForEach(DisplayItem.allCases) { item in
                        MenuToggleRow(icon: "circle.grid.2x2", label: tr(item.titleKey),
                                      isOn: preferences.isVisible(item), isNested: true) {
                            preferences.setVisible(!preferences.isVisible(item), for: item)
                        }
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // System settings
                MenuToggleRow(
                    icon: "power",
                    label: tr("menu.launchAtLogin"),
                    isOn: launchAtLogin
                ) {
                    loginError = nil
                    if AppRuntime.isPreview {
                        launchAtLogin.toggle()
                        return
                    }
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.unregister()
                            launchAtLogin = false
                        } else {
                            try SMAppService.mainApp.register()
                            launchAtLogin = true
                        }
                    } catch {
                        loginError = "\(tr("menu.launchAtLoginFailed")): \(error.localizedDescription)"
                    }
                }
                if let loginError { feedbackRow(loginError) }

                Button {
                    isHooksExpanded.toggle()
                    viewModel.hookListExpanded = isHooksExpanded
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 16)

                        Text(tr("menu.agentHooks"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Image(systemName: isHooksExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)

                if isHooksExpanded {
                    MenuToggleRow(source: .claude, label: "Claude", isOn: hookState(for: .claude), isNested: true) {
                        toggleHook(.claude)
                    }
                    MenuToggleRow(source: .codex, label: "Codex", isOn: hookState(for: .codex), isNested: true) {
                        toggleHook(.codex)
                    }
                    MenuToggleRow(source: .cursor, label: "Cursor", isOn: hookState(for: .cursor), isNested: true) {
                        toggleHook(.cursor)
                    }
                    MenuToggleRow(source: .copilot, label: "GitHub Copilot", isOn: hookState(for: .githubCopilot), isNested: true) {
                        toggleHook(.githubCopilot)
                    }
                    MenuToggleRow(source: .pi, label: "Pi", isOn: hookState(for: .pi), isNested: true) {
                        toggleHook(.pi)
                    }
                    MenuToggleRow(source: .opencode, label: "OpenCode", isOn: hookState(for: .openCode), isNested: true) {
                        toggleHook(.openCode)
                    }
                    MenuToggleRow(source: .workbuddy, label: "WorkBuddy", isOn: hookState(for: .workBuddy), isNested: true) {
                        toggleHook(.workBuddy)
                    }
                }
                if let hookError { feedbackRow(hookError) }

                AccessibilityRow()

                sectionRow(.tibo, icon: "bell", label: "Tibo")
                if expandedSection == .tibo {
                    MenuToggleRow(icon: "network", label: tr("menu.tiboNetworking"),
                                  isOn: preferences.tiboNetworking, isNested: true) {
                        preferences.tiboNetworking.toggle()
                    }
                    MenuToggleRow(icon: "bell.badge", label: tr("menu.tiboNotifications"),
                                  isOn: preferences.tiboNotifications, isNested: true) {
                        preferences.tiboNotifications.toggle()
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // About
                VersionRow(label: tr("menu.version"))

                MenuRow(icon: "arrow.up.circle", label: updateLabel) {
                    handleUpdateAction()
                }

                MenuRow(icon: "questionmark.circle", label: tr("menu.help")) {
                    openExternalPage("https://github.com/section9-lab/VibeHUD#readme")
                }

                MenuRow(
                    icon: "star",
                    label: tr("menu.starGitHub")
                ) {
                    openExternalPage("https://github.com/section9-lab/VibeHUD")
                }
                if let linkError { feedbackRow(linkError) }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                MenuRow(
                    icon: "xmark.circle",
                    label: tr("menu.quit"),
                    isDestructive: true
                ) {
                    if !AppRuntime.isPreview {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MenuContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(MenuContentHeightPreferenceKey.self) {
            viewModel.updateMenuContentHeight($0)
        }
        .onAppear {
            isHooksExpanded = viewModel.hookListExpanded
            refreshStates()
        }
        .onChange(of: viewModel.contentType) { _, newValue in
            if newValue == .menu {
                refreshStates()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshStates()
        }
    }

    private func refreshStates() {
        guard !AppRuntime.isPreview else { return }
        hookStates = Dictionary(uniqueKeysWithValues: HookAgent.allCases.map {
            ($0, HookInstaller.isInstalled($0))
        })
        launchAtLogin = SMAppService.mainApp.status == .enabled
        screenSelector.refreshScreens()
    }

    private func hookState(for agent: HookAgent) -> Bool {
        hookStates[agent, default: false]
    }

    private func toggleHook(_ agent: HookAgent) {
        hookError = nil
        if AppRuntime.isPreview {
            hookStates[agent] = !hookState(for: agent)
            return
        }
        let shouldInstall = !hookState(for: agent)
        if hookState(for: agent) {
            HookInstaller.uninstall(agent)
        } else {
            HookInstaller.install(agent)
        }
        hookStates[agent] = HookInstaller.isInstalled(agent)
        if hookStates[agent] != shouldInstall {
            hookError = tr("menu.agentHooksFailed")
        }
    }

    private func openExternalPage(_ address: String) {
        linkError = nil
        guard !AppRuntime.isPreview else { return }
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else {
            linkError = tr("menu.openPageFailed")
            return
        }
    }

    private var updateLabel: String {
        if AppRuntime.isLocalBuild || AppRuntime.isPreview {
            return tr("menu.checkUpdatesReleases")
        }
        switch updateManager.state {
        case .idle, .upToDate: return tr("menu.checkUpdates")
        case .checking: return tr("menu.checkingUpdates")
        case .found: return tr("menu.downloadUpdate")
        case .downloading: return tr("menu.downloadingUpdate")
        case .extracting: return tr("menu.extractingUpdate")
        case .readyToInstall: return tr("menu.installUpdate")
        case .installing: return tr("menu.installingUpdate")
        case .error: return tr("menu.updateFailed")
        }
    }

    private func handleUpdateAction() {
        if AppRuntime.isLocalBuild || AppRuntime.isPreview {
            openExternalPage("https://github.com/section9-lab/VibeHUD/releases")
            return
        }
        switch updateManager.state {
        case .idle, .upToDate, .error: updateManager.checkForUpdates()
        case .found: updateManager.downloadAndInstall()
        case .readyToInstall: updateManager.installAndRelaunch()
        default: break
        }
    }

    private func feedbackRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundColor(Color(red: 1, green: 0.58, blue: 0.58))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private func sectionRow(_ section: MenuSection, icon: String, label: String, detail: String? = nil) -> some View {
        Button {
            expandedSection = expandedSection == section ? nil : section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local Version Row

struct VersionRow: View {
    let label: String

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Accessibility Permission Row

struct AccessibilityRow: View {
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var isHovered = false
    @State private var refreshTrigger = false
    @State private var previewEnabled = false
    @State private var openError: String?

    private var currentlyEnabled: Bool {
        _ = refreshTrigger
        return AppRuntime.isPreview ? previewEnabled : AXIsProcessTrusted()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(AppLocalization.string("menu.accessibility", language: preferences.language))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                if currentlyEnabled {
                    Circle()
                        .fill(TerminalColors.green)
                        .frame(width: 6, height: 6)

                    Text(AppLocalization.string("menu.enabled", language: preferences.language))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Button(action: openAccessibilitySettings) {
                        Text(AppLocalization.string("menu.enable", language: preferences.language))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .onHover { isHovered = $0 }
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                refreshTrigger.toggle()
            }
            if let openError {
                Text(openError)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.58, blue: 0.58))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func openAccessibilitySettings() {
        openError = nil
        if AppRuntime.isPreview {
            previewEnabled.toggle()
            return
        }
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            if !NSWorkspace.shared.open(url) {
                openError = AppLocalization.string("menu.accessibilityFailed", language: preferences.language)
            }
        } else {
            openError = AppLocalization.string("menu.accessibilityFailed", language: preferences.language)
        }
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        if isDestructive {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
        return .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

struct MenuToggleRow: View {
    @ObservedObject private var preferences = AppPreferences.shared
    let icon: String?
    let source: SessionSource?
    let label: String
    let isOn: Bool
    let isNested: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        icon: String,
        label: String,
        isOn: Bool,
        isNested: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.source = nil
        self.label = label
        self.isOn = isOn
        self.isNested = isNested
        self.action = action
    }

    init(
        source: SessionSource,
        label: String,
        isOn: Bool,
        isNested: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = nil
        self.source = source
        self.label = label
        self.isOn = isOn
        self.isNested = isNested
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let source {
                    AgentBrandIcon(source: source, style: .monochrome, size: 14)
                        .frame(width: 16)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)
                }

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Circle()
                    .fill(isOn ? TerminalColors.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(AppLocalization.string(isOn ? "menu.enabled" : "menu.disabled",
                                            language: preferences.language))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.leading, isNested ? 16 : 0)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}
