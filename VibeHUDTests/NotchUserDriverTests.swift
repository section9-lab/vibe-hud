import Foundation
import Testing
@testable import vibe_hud

@Suite("Sparkle update status", .serialized)
@MainActor
struct NotchUserDriverTests {
    @Test("Download and extraction callbacks preserve their order")
    func progressCallbacksAreSynchronous() {
        let manager = UpdateManager.shared
        let driver = NotchUserDriver()
        manager.state = .idle
        defer { manager.state = .idle }

        driver.showDownloadInitiated(cancellation: {})
        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 100)
        #expect(manager.state == .downloading(progress: 1))

        driver.showDownloadDidStartExtractingUpdate()
        driver.showExtractionReceivedProgress(0.5)
        #expect(manager.state == .extracting(progress: 0.5))
    }

    @Test("An acknowledged update failure stays visible after Sparkle dismisses installation")
    func failureSurvivesDismissal() {
        let manager = UpdateManager.shared
        let driver = NotchUserDriver()
        manager.state = .extracting(progress: 0)
        defer { manager.state = .idle }
        let error = NSError(domain: "SUSparkleErrorDomain", code: 3001,
                            userInfo: [NSLocalizedDescriptionKey: "Update signature is invalid"])
        var acknowledged = false

        driver.showUpdaterError(error) {
            acknowledged = true
            #expect(manager.state == .error(message: error.localizedDescription))
            driver.dismissUpdateInstallation()
        }

        #expect(acknowledged)
        #expect(manager.state == .error(message: error.localizedDescription))

        driver.showUserInitiatedUpdateCheck(cancellation: {})
        #expect(manager.state == .checking)
    }
}
