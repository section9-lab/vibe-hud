//
//  Settings.swift
//  VibeHUD
//
//  App settings manager using UserDefaults
//

import Combine
import Foundation

enum AppRuntime {
    static let isLocalBuild = Bundle.main.object(forInfoDictionaryKey: "VibeHUDLocalBuild") as? Bool == true
    static let requiresTakeover = Bundle.main.object(forInfoDictionaryKey: "VibeHUDRequiresTakeover") as? Bool == true
    static var isPreview: Bool { Foundation.ProcessInfo.processInfo.arguments.contains("--preview")
        || Foundation.ProcessInfo.processInfo.environment["FDAR_USAGE_PREVIEW"] == "1"
    }
    static let previewSuite = (Bundle.main.bundleIdentifier ?? "com.section9lab.VibeHUD") + ".preview"
}

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }

    @MainActor var displayName: String {
        AppLocalization.string("sound.\(rawValue.lowercased())")
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

enum DisplayItem: String, CaseIterable, Identifiable {
    case claudeFiveHour = "claude5h"
    case claudeSevenDay = "claude7d"
    case claudeSpeed = "claudeSpeed"
    case codexQuota = "codexQuota"
    case codexSpeed = "codexSpeed"
    case tiboEntry = "tiboEntry"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .claudeFiveHour: "quota.title.claude.fiveHour"
        case .claudeSevenDay: "quota.title.claude.sevenDay"
        case .claudeSpeed: "display.claudeSpeed"
        case .codexQuota: "display.codexQuota"
        case .codexSpeed: "display.codexSpeed"
        case .tiboEntry: "display.tiboEntry"
        }
    }

    fileprivate var legacyKey: String? {
        switch self {
        case .claudeFiveHour: "c5"
        case .claudeSevenDay: "c7"
        case .codexQuota: "x7"
        case .codexSpeed, .claudeSpeed, .tiboEntry: nil
        }
    }
}

/// App-owned, observable settings. View-only switches never control the workers or hooks.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared: AppPreferences = {
        if AppRuntime.isPreview {
            return AppPreferences(defaults: UserDefaults(suiteName: AppRuntime.previewSuite)!, legacyDefaults: nil)
        }
        return AppPreferences()
    }()

    private enum Key {
        static let language = "usageHUD.language"
        static let displayPrefix = "usageHUD.display."
        static let tiboNetworking = "usageHUD.tiboNetworking"
        static let tiboNotifications = "usageHUD.tiboNotifications"
    }

    private let defaults: UserDefaults

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }
    @Published var visibleItems: Set<DisplayItem> {
        didSet {
            for item in DisplayItem.allCases {
                defaults.set(visibleItems.contains(item), forKey: Key.displayPrefix + item.rawValue)
            }
        }
    }
    @Published var tiboNetworking: Bool {
        didSet { defaults.set(tiboNetworking, forKey: Key.tiboNetworking) }
    }
    @Published var tiboNotifications: Bool {
        didSet { defaults.set(tiboNotifications, forKey: Key.tiboNotifications) }
    }

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        let legacyVisibleItems = legacyDefaults?.dictionary(forKey: "usageHUD.visibleItems") ?? [:]
        let enabled = DisplayItem.allCases.filter { item in
            let key = Key.displayPrefix + item.rawValue
            if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
            if let legacyKey = item.legacyKey, let value = legacyVisibleItems[legacyKey] as? Bool {
                return value
            }
            return true
        }
        visibleItems = Set(enabled)
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .simplifiedChinese
        let legacyTiboEnabled = (legacyDefaults?.object(forKey: "usageHUD.resetAlerts") as? Bool) ?? true
        tiboNetworking = Self.bool(defaults, Key.tiboNetworking, fallback: legacyTiboEnabled)
        tiboNotifications = Self.bool(defaults, Key.tiboNotifications,
                                      fallback: legacyTiboEnabled)
        // Record the first-run language and imported choices so later legacy changes cannot override them.
        defaults.set(language.rawValue, forKey: Key.language)
        for item in DisplayItem.allCases {
            defaults.set(visibleItems.contains(item), forKey: Key.displayPrefix + item.rawValue)
        }
        defaults.set(tiboNetworking, forKey: Key.tiboNetworking)
        defaults.set(tiboNotifications, forKey: Key.tiboNotifications)
    }

    func isVisible(_ item: DisplayItem) -> Bool { visibleItems.contains(item) }

    func setVisible(_ visible: Bool, for item: DisplayItem) {
        if visible { visibleItems.insert(item) } else { visibleItems.remove(item) }
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}

enum AppSettings {
    private static let defaults = AppRuntime.isPreview
        ? UserDefaults(suiteName: AppRuntime.previewSuite)!
        : UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                let sound = NotificationSound(rawValue: rawValue)
            else {
                return .pop  // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

}
