import AppKit
import SwiftUI

enum MonitoringNumberText {
    static func speedNumber(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "--" }
        let number: String
        if value < 0.1 { number = "<0.1" }
        else if value >= 1e12 { number = String(format: "%.1e", value) }
        else if value >= 1e9 { number = String(format: "%.1fG", value / 1e9) }
        else if value >= 1e6 { number = String(format: "%.1fM", value / 1e6) }
        else if value >= 1e3 { number = String(format: "%.1fk", value / 1e3) }
        else { number = String(format: "%.1f", value) }
        return number
    }

    static func speed(_ value: Double?) -> String { speedNumber(value) + " tok/s" }

    static func ringSpeedNumber(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "--" }
        if value < 0.1 { return "<0.1" }
        if value < 1 { return String(format: "%.1f", value) }
        if value < 1_000 { return String(Int(value.rounded())) }
        if value < 1_000_000 { return String(format: "%.0fk", value / 1_000) }
        return String(format: "%.0fM", value / 1_000_000)
    }
}

enum MonitoringRingTone: Equatable {
    case unknown, green, gold, red

    init(remaining: Double?) {
        guard let remaining, remaining.isFinite else { self = .unknown; return }
        if remaining <= 5 { self = .red }
        else if remaining <= 20 { self = .gold }
        else { self = .green }
    }
}

enum MonitoringRingLayout {
    static let stroke: CGFloat = 2.1

    static func outerDiameter(notchHeight: CGFloat) -> CGFloat {
        min(NotchAccessory.ringDiameter, max(0, notchHeight - 4))
    }

    static func innerDiameter(outerDiameter: CGFloat) -> CGFloat {
        max(0, outerDiameter - 6)
    }
}

enum MonitoringCenterCycle {
    static func showsIcon(at date: Date) -> Bool {
        Int(floor(date.timeIntervalSinceReferenceDate / 5)).isMultiple(of: 2) == false
    }
}

struct ClosedMonitoringAccessory: View {
    let accessory: NotchAccessory
    @ObservedObject var store: MonitoringStore
    @ObservedObject var preferences: AppPreferences
    let notchHeight: CGFloat

    private var quotaSnapshot: QuotaSnapshot {
        accessory == .codex ? store.codex : store.claude
    }

    private var displayedPeriods: [QuotaPeriod] {
        switch accessory {
        case .codex:
            guard preferences.isVisible(.codexQuota) else { return [] }
            return QuotaPeriod.allCases.filter { quotaSnapshot.window($0) != nil }
        case .claude:
            return QuotaPeriod.allCases.filter { period in
                preferences.isVisible(period == .fiveHour ? .claudeFiveHour : .claudeSevenDay)
            }
        default: return []
        }
    }

    private func remaining(for window: QuotaWindow?) -> Double? {
        guard let window, !window.isStale, window.remainingPercent.isFinite else { return nil }
        return min(100, max(0, window.remainingPercent))
    }

    private func ringColor(for remaining: Double?) -> Color {
        switch MonitoringRingTone(remaining: remaining) {
        case .unknown: Color(red: 0.57, green: 0.58, blue: 0.60)
        case .red: Color(red: 0.925, green: 0.467, blue: 0.459)
        case .gold: Color(red: 0.91, green: 0.757, blue: 0.427)
        case .green: Color(red: 0.647, green: 0.871, blue: 0.761)
        }
    }

    private func trackColor(for remaining: Double?) -> Color {
        guard let remaining else { return ringColor(for: nil) }
        return remaining == 0 ? Color(red: 0.478, green: 0.231, blue: 0.243)
            : Color(red: 0.27, green: 0.278, blue: 0.294)
    }

    var body: some View {
        ZStack {
            if accessory == .codex || accessory == .claude {
                ring
            } else {
                Image(systemName: accessory == .tibo ? "bell" : "square.grid.2x2")
                    .font(.system(size: 12))
                    .overlay(alignment: .topTrailing) {
                        if preferences.isVisible(.tiboEntry), preferences.tiboNotifications,
                           store.tibo.shouldPresent { unreadDot }
                    }
            }
        }
        .frame(width: accessory.width, height: notchHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var ring: some View {
        let outer = MonitoringRingLayout.outerDiameter(notchHeight: notchHeight)
        return ZStack {
            if displayedPeriods.count == 2 {
                ringLayer(diameter: outer, window: quotaSnapshot.window(.fiveHour))
                ringLayer(diameter: MonitoringRingLayout.innerDiameter(outerDiameter: outer),
                          window: quotaSnapshot.window(.sevenDay))
            } else {
                ringLayer(diameter: outer, window: displayedPeriods.first.flatMap(quotaSnapshot.window))
            }

            if accessory == .codex {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 5)) { context in
                    if MonitoringCenterCycle.showsIcon(at: context.date) {
                        brandIcon(size: displayedPeriods.count == 2 ? 10.5 : 12)
                    } else {
                        VStack(spacing: -1) {
                            Text(codexCenterNumber)
                                .font(.system(size: displayedPeriods.count == 2 ? 7.2 : 9,
                                              weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(preferences.isVisible(.codexSpeed) ? "tok/s" : codexCenterPeriod)
                                .font(.system(size: displayedPeriods.count == 2 ? 4 : 4.8,
                                              weight: .medium))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        .foregroundStyle(.white.opacity(0.96))
                    }
                }
            } else if preferences.isVisible(.claudeSpeed), store.claude.tokensPerSecond != nil {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 5)) { context in
                    if MonitoringCenterCycle.showsIcon(at: context.date) {
                        brandIcon(size: displayedPeriods.count == 2 ? 10.5 : 12)
                    } else {
                        VStack(spacing: -1) {
                            Text(MonitoringNumberText.ringSpeedNumber(store.claude.tokensPerSecond))
                                .font(.system(size: displayedPeriods.count == 2 ? 7.2 : 9,
                                              weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("tok/s")
                                .font(.system(size: displayedPeriods.count == 2 ? 4 : 4.8,
                                              weight: .medium))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        .foregroundStyle(.white.opacity(0.96))
                    }
                }
            } else {
                brandIcon(size: displayedPeriods.count == 2 ? 10.5 : 12)
            }
        }
        .frame(width: outer, height: outer)
    }

    private var codexCenterNumber: String {
        if preferences.isVisible(.codexSpeed) {
            return MonitoringNumberText.ringSpeedNumber(store.codex.tokensPerSecond)
        }
        let value = displayedPeriods.first.flatMap { remaining(for: store.codex.window($0)) }
        return value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    private var codexCenterPeriod: String {
        displayedPeriods.first == .fiveHour ? "5h" : "7d"
    }

    private func ringLayer(diameter: CGFloat, window: QuotaWindow?) -> some View {
        let remaining = remaining(for: window)
        let stroke = MonitoringRingLayout.stroke
        return ZStack {
            Circle()
                .strokeBorder(trackColor(for: remaining), lineWidth: stroke)
            if let remaining, remaining > 0 {
                Circle()
                    .trim(from: 0, to: remaining / 100)
                    .stroke(ringColor(for: remaining),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(stroke / 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func brandIcon(size: CGFloat) -> some View {
        AgentBrandIcon(source: accessory == .codex ? .codex : .claude,
                       style: .colored, size: size)
            .accessibilityHidden(true)
    }

    private var unreadDot: some View {
        Circle().fill(TerminalColors.green).frame(width: 5, height: 5).offset(x: 4, y: -4)
    }

    private func quotaAccessibility(_ period: QuotaPeriod, window: QuotaWindow?) -> String {
        let label = period == .fiveHour ? "5h" : "7d"
        guard let window else {
            return label + ", " + AppLocalization.string("monitoring.unavailable", language: preferences.language)
        }
        guard window.remainingPercent.isFinite else {
            return label + ", " + AppLocalization.string("monitoring.unavailable", language: preferences.language)
        }
        let valueKey = window.isStale ? "monitoring.lastRecorded" : "monitoring.remaining"
        return "\(label), \(AppLocalization.string(valueKey, language: preferences.language)) \(Int(window.remainingPercent.rounded()))%"
    }

    private var accessibilityLabel: String {
        let key: String
        switch accessory {
        case .codex: key = "display.codexQuota"
        case .claude: key = "display.claudeFiveHour"
        case .tibo: key = "display.tiboEntry"
        case .more: key = "menu.display"
        }
        let label = AppLocalization.string(key, language: preferences.language)
        switch accessory {
        case .codex:
            let quotaLabel = preferences.isVisible(.codexQuota)
                ? (displayedPeriods.isEmpty
                   ? AppLocalization.string("monitoring.unavailable", language: preferences.language)
                   : displayedPeriods.map { quotaAccessibility($0, window: quotaSnapshot.window($0)) }
                       .joined(separator: ", "))
                : AppLocalization.string("display.codexSpeed", language: preferences.language)
            return preferences.isVisible(.codexSpeed)
                ? "Codex, " + quotaLabel + ", " + MonitoringNumberText.speed(store.codex.tokensPerSecond)
                : "Codex, " + quotaLabel
        case .claude:
            let quotaLabel = displayedPeriods.map {
                quotaAccessibility($0, window: quotaSnapshot.window($0))
            }.joined(separator: ", ")
            if preferences.isVisible(.claudeSpeed) {
                return "Claude, " + quotaLabel + ", " + MonitoringNumberText.speed(store.claude.tokensPerSecond)
            }
            return "Claude, " + quotaLabel
        default:
            return label
        }
    }
}

struct MonitoringNotchContent: View {
    let panel: NotchMonitoringPanel
    @ObservedObject var store: MonitoringStore
    @ObservedObject var preferences: AppPreferences
    let onBack: () -> Void
    let onSelect: (NotchMonitoringPanel) -> Void
    let onPresented: () -> Void

    private func tr(_ key: String) -> String {
        AppLocalization.string(key, language: preferences.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("menu.back"))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.82))

            Divider().overlay(.white.opacity(0.1))

            switch panel {
            case .claude:
                quotaDetails(snapshot: store.claude, source: .claude)
            case .codex:
                quotaDetails(snapshot: store.codex, source: .codex)
            case .speed:
                speedDetails
            case .tibo:
                tiboDetails
            case .overview:
                overviewDetails
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: onPresented)
    }

    private var title: String {
        switch panel {
        case .claude: "Claude"
        case .codex, .speed: "Codex"
        case .tibo: "Tibo"
        case .overview: tr("menu.display")
        }
    }

    private func quotaDetails(snapshot: QuotaSnapshot, source: SessionSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if (source == .claude && preferences.isVisible(.claudeFiveHour) &&
                preferences.isVisible(.claudeSevenDay)) ||
               (source == .codex && preferences.isVisible(.codexQuota) &&
                snapshot.window(.fiveHour) != nil && snapshot.window(.sevenDay) != nil) {
                Text(tr("monitoring.ringOrder"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.52))
            }
            if source == .claude, preferences.isVisible(.claudeFiveHour) {
                quotaRow(snapshot: snapshot, period: .fiveHour, title: "5h", source: source)
            }
            if source == .codex, preferences.isVisible(.codexQuota),
               snapshot.window(.fiveHour) != nil {
                quotaRow(snapshot: snapshot, period: .fiveHour, title: "5h", source: source)
            }
            if (source == .claude && preferences.isVisible(.claudeSevenDay)) ||
               (source == .codex && preferences.isVisible(.codexQuota) &&
                snapshot.window(.sevenDay) != nil) {
                quotaRow(snapshot: snapshot, period: .sevenDay, title: "7d", source: source)
            }
            if source == .codex, preferences.isVisible(.codexQuota), snapshot.windows.isEmpty {
                Text(tr("monitoring.unavailable"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if (source == .codex && preferences.isVisible(.codexSpeed)) ||
               (source == .claude && preferences.isVisible(.claudeSpeed)) {
                HStack {
                    Text(tr("monitoring.todaySpeed"))
                    Spacer()
                    Text(MonitoringNumberText.speed(snapshot.tokensPerSecond))
                }
                .font(.system(size: 12))
            }
            if source == .claude || preferences.isVisible(.codexQuota) {
                freshness(snapshot.updatedAt, stale: snapshot.windows.values.contains { $0.isStale },
                          hasError: snapshot.errorCode != nil)
            } else {
                Text(tr("monitoring.speedDefinition"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func quotaRow(snapshot: QuotaSnapshot, period: QuotaPeriod,
                          title: String, source: SessionSource) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                AgentBrandIcon(source: source, style: .colored, size: 14)
                Text(title).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if let window = snapshot.window(period) {
                    Text("\(tr(window.isStale ? "monitoring.lastRecorded" : "monitoring.remaining")) \(Int(window.remainingPercent.rounded()))%")
                        .fontWeight(.semibold)
                        .foregroundStyle(window.isStale ? .gray : .white)
                } else {
                    Text(tr("monitoring.unavailable")).foregroundStyle(.white.opacity(0.45))
                }
            }
            .font(.system(size: 12))
            if let window = snapshot.window(period) {
                HStack(spacing: 5) {
                    Text("\(tr("monitoring.used")) \(Int(window.usedPercent.rounded()))%")
                    if let reset = window.resetsAt {
                        Text("·")
                        Text(tr("monitoring.resets"))
                        Text(reset, style: .relative)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 22)
            }
        }
    }

    private var speedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("monitoring.todaySpeed"))
                Spacer()
                Text(MonitoringNumberText.speed(store.codex.tokensPerSecond))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 12))
            Text(tr("monitoring.speedDefinition"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var tiboDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.tibo.isStale || store.tibo.errorCode != nil {
                Label(tr(store.tibo.errorCode != nil ? "monitoring.sourceUnavailable" : "monitoring.stale"),
                      systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(TerminalColors.amber)
            }
            if let alert = store.tibo.alert {
                Text(tr("monitoring.tibo." + alert.kind))
                    .font(.system(size: 13, weight: .semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(alert.text)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alert.postedAt, style: .date)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxHeight: 150)
                HStack {
                    Text(tr("monitoring.tibo.source"))
                    Spacer()
                    Button { NSWorkspace.shared.open(alert.url) } label: {
                        HStack(spacing: 3) {
                            Text("X")
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("monitoring.tibo.openOriginal"))
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.68))
                Text(tr("monitoring.tibo.disclaimer"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("monitoring.unavailable")).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var overviewDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if preferences.isVisible(.claudeFiveHour) || preferences.isVisible(.claudeSevenDay)
                    || preferences.isVisible(.claudeSpeed) {
                    Button { onSelect(.claude) } label: {
                        quotaDetails(snapshot: store.claude, source: .claude)
                    }
                    .buttonStyle(.plain)
                }
                if preferences.isVisible(.codexQuota) || preferences.isVisible(.codexSpeed) {
                    Button { onSelect(.codex) } label: {
                        quotaDetails(snapshot: store.codex, source: .codex)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 16) {
                    if preferences.isVisible(.tiboEntry) {
                        Button { onSelect(.tibo) } label: {
                            Label(tr("display.tiboEntry"), systemImage: "bell")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 11))
            }
        }
        .frame(maxHeight: 245)
    }

    @ViewBuilder
    private func freshness(_ updatedAt: Date?, stale: Bool, hasError: Bool) -> some View {
        if hasError {
            Label(tr("monitoring.sourceUnavailable"), systemImage: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(TerminalColors.amber)
        } else if stale {
            Label(tr("monitoring.stale"), systemImage: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(TerminalColors.amber)
        }
        if let updatedAt {
            HStack(spacing: 4) {
                Text(tr("monitoring.updated"))
                Text(updatedAt, style: .relative)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.42))
        }
    }
}
