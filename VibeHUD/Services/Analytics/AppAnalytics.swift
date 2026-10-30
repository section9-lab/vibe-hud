import Combine
import Foundation
import Mixpanel

@MainActor
final class AppAnalytics: ObservableObject {
    static let shared = AppAnalytics()
    static let appID = "vibe-hud"

    #if DEBUG
        private static let environment = "development"
    #else
        private static let environment = "production"
    #endif

    private static var reportingDestination: String {
        Bundle.main.object(forInfoDictionaryKey: "MixpanelProjectID") as? String ?? "legacy"
    }

    @Published private(set) var isEnabled: Bool
    private let state: AnalyticsState
    private var client: MixpanelInstance?

    private init() {
        // Must match the shared project's reporting timezone (currently US/Pacific).
        state = AnalyticsState(
            appID: "\(Self.appID).\(Self.environment)",
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        isEnabled = state.isEnabled
    }

    func start() {
        guard client == nil, isEnabled,
            Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            let token = Bundle.main.object(forInfoDictionaryKey: "MixpanelProjectToken") as? String,
            !token.isEmpty
        else { return }

        let installationID = "\(Self.appID):\(state.installationID)"
        let options = MixpanelOptions(
            token: token,
            instanceName: "\(Self.appID)-\(Self.environment)-usage-\(Self.reportingDestination)",
            trackAutomaticEvents: false,
            useUniqueDistinctId: false,
            superProperties: commonProperties,
            serverURL: "https://api.mixpanel.com",
            deviceIdProvider: { installationID }
        )
        let instance = Mixpanel.initialize(options: options)
        instance.useIPAddressForGeoLocation = false
        if instance.hasOptedOutTracking() {
            instance.optInTracking()
        }
        // Anonymous device metrics do not need Mixpanel People profiles.
        instance.identify(distinctId: installationID, usePeople: false)
        client = instance
        instance.track(event: "App Launched")
        instance.flush()
    }

    /// Called for actual HUD interactions, never for background agent events.
    func recordActivity(at date: Date = Date()) {
        guard isEnabled, let client,
            let day = state.claimActiveDay(at: date, destination: Self.reportingDestination)
        else { return }
        // Refresh regional hints when settings change while the app remains open.
        client.registerSuperProperties(commonProperties)
        client.track(event: "Daily Active", properties: ["activity_date": day])
        client.flush()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        state.isEnabled = enabled
        isEnabled = enabled
        if enabled {
            if let client {
                client.optInTracking()
                client.registerSuperProperties(commonProperties)
                client.identify(
                    distinctId: "\(Self.appID):\(state.installationID)", usePeople: false)
            } else {
                start()
            }
            recordActivity()
        } else {
            client?.optOutTracking()
        }
    }

    func flush() {
        guard isEnabled else { return }
        client?.flush()
    }

    private var commonProperties: Properties {
        var properties: Properties = [:]
        for (key, value) in AnalyticsRegionContext().properties {
            properties[key] = value
        }
        let appProperties: Properties = [
            "app_id": Self.appID,
            "app_name": "vibe hud",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "unknown",
            "build_number": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? "unknown",
            "platform": "macOS",
            "environment": Self.environment,
            "macos_version": Foundation.ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        return properties.merging(appProperties) { _, appValue in appValue }
    }
}
