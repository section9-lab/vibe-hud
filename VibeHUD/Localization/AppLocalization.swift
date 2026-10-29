import Foundation

@MainActor
enum AppLocalization {
    static func string(_ key: String) -> String {
        string(key, language: AppPreferences.shared.language)
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        #if SWIFT_PACKAGE
        let packaged = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("VibeHUDLocal_VibeHUDLocal.bundle", isDirectory: true))
        }
        let resources = Bundle.main.bundleURL.pathExtension == "app"
            ? (packaged ?? Bundle.main) : Bundle.module
        #else
        let resources = Bundle.main
        #endif
        let path = resources.path(forResource: language.rawValue, ofType: "lproj")
            ?? resources.path(forResource: language.rawValue.lowercased(), ofType: "lproj")
            ?? resources.path(forResource: language.rawValue, ofType: "lproj", inDirectory: "Localization")
        let bundle = path.flatMap(Bundle.init(path:)) ?? resources
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
