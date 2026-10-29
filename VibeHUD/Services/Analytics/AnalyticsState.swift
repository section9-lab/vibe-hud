import Foundation

/// Local bookkeeping only. No hardware identifiers or conversation data are read.
@MainActor
final class AnalyticsState {
    private let defaults: UserDefaults
    private let prefix: String
    private var calendar: Calendar

    init(defaults: UserDefaults = .standard, appID: String, timeZone: TimeZone) {
        self.defaults = defaults
        prefix = "analytics.\(appID)."
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: prefix + "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    var installationID: String {
        let key = prefix + "installation_id"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        // Earlier releases stored the Mac's hardware UUID. Never reuse or send it.
        defaults.removeObject(forKey: "mixpanel_distinct_id")
        return id
    }

    /// Persist across restarts; use the Mixpanel project's timezone, including DST.
    func claimActiveDay(at date: Date) -> String? {
        guard isEnabled else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day
        else {
            return nil
        }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        let key = prefix + "last_active_day"
        guard defaults.string(forKey: key) != dayKey else { return nil }
        defaults.set(dayKey, forKey: key)
        return dayKey
    }
}
