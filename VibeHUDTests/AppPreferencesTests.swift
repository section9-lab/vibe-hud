import Foundation
import Testing
@testable import vibe_hud

@Suite("App preferences", .serialized)
@MainActor
struct AppPreferencesTests {
    @Test("Legacy booleans migrate without merging display and network choices")
    func firstRunMigration() {
        let app = temporaryDefaults(appSuiteName)
        let legacy = temporaryDefaults(legacySuiteName)
        defer {
            app.removePersistentDomain(forName: appSuiteName)
            legacy.removePersistentDomain(forName: legacySuiteName)
        }
        legacy.set(["c5": false, "c7": true, "x7": "false", "cpu": false],
                   forKey: "usageHUD.visibleItems")
        legacy.set(false, forKey: "usageHUD.resetAlerts")

        let preferences = AppPreferences(defaults: app, legacyDefaults: legacy)

        #expect(preferences.language == .simplifiedChinese)
        #expect(!preferences.isVisible(.claudeFiveHour))
        #expect(preferences.isVisible(.claudeSevenDay))
        #expect(preferences.isVisible(.codexQuota))
        #expect(preferences.isVisible(.codexSpeed))
        #expect(preferences.isVisible(.tiboEntry))
        #expect(!preferences.tiboNetworking)
        #expect(!preferences.tiboNotifications)

        preferences.setVisible(false, for: .tiboEntry)
        #expect(!preferences.tiboNetworking)
    }

    @Test("Native choices persist and outrank legacy values")
    func nativeChoicesPersist() {
        let app = temporaryDefaults(appSuiteName)
        let legacy = temporaryDefaults(legacySuiteName)
        defer {
            app.removePersistentDomain(forName: appSuiteName)
            legacy.removePersistentDomain(forName: legacySuiteName)
        }
        legacy.set(["c5": false], forKey: "usageHUD.visibleItems")
        let first = AppPreferences(defaults: app, legacyDefaults: legacy)
        first.language = .english
        first.setVisible(true, for: .claudeFiveHour)
        first.tiboNetworking = false

        let second = AppPreferences(defaults: app, legacyDefaults: legacy)
        #expect(second.language == .english)
        #expect(second.isVisible(.claudeFiveHour))
        #expect(!second.tiboNetworking)
    }

    private var appSuiteName: String { "AppPreferencesTests.app" }
    private var legacySuiteName: String { "AppPreferencesTests.legacy" }

    private func temporaryDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
