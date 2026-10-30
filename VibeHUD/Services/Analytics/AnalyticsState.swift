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
    func claimActiveDay(at date: Date, destination: String = "legacy") -> String? {
        guard isEnabled else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day
        else {
            return nil
        }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        // A project migration must not suppress the first active day in its new destination.
        let key = prefix + "last_active_day" + (destination == "legacy" ? "" : "." + destination)
        guard defaults.string(forKey: key) != dayKey else { return nil }
        defaults.set(dayKey, forKey: key)
        return dayKey
    }
}

/// Device settings are regional hints, never a claim about physical location.
/// Do not infer a country from a language or a timezone shared by many countries.
struct AnalyticsRegionContext {
    let countrySetting: String
    let language: String
    let timeZoneIdentifier: String

    init(
        locale: Locale = .autoupdatingCurrent,
        preferredLanguages: [String] = Locale.preferredLanguages,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        let region = locale.region?.identifier.uppercased() ?? ""
        countrySetting = region.count == 2 && Locale.Region.isoRegions.contains {
            $0.identifier == region
        } ? region : "unknown"
        let preferredLanguage = preferredLanguages.first.flatMap { value in
            value.isEmpty ? nil : Locale(identifier: value).language.languageCode?.identifier
        }
        language = preferredLanguage ?? locale.language.languageCode?.identifier ?? "unknown"
        timeZoneIdentifier = timeZone.identifier
    }

    var properties: [String: String] {
        [
            "device_region_country": countrySetting,
            "device_language": language,
            "device_timezone": timeZoneIdentifier,
            "region_source": countrySetting == "unknown" ? "unknown" : "system_region_setting",
        ]
    }
}
