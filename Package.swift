// swift-tools-version: 6.1
// Command Line Tools build probe. Xcode remains the authoritative project.
import PackageDescription

let package = Package(
    name: "VibeHUDLocal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VibeHUDLocal", targets: ["VibeHUDLocal"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.7.3"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "VibeHUDLocal",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "VibeHUD",
            exclude: ["Info.plist", "Assets.xcassets", "Resources"],
            swiftSettings: [.define("VIBEHUD_LOCAL")]
        )
    ],
    swiftLanguageModes: [.v5]
)
