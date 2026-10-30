import Foundation
import Sparkle
import Testing
@testable import vibe_hud

@Suite("Sparkle update status", .serialized)
@MainActor
struct NotchUserDriverTests {
    @Test("A nonisolated app delegate initializer can construct the stateless driver")
    nonisolated func driverCanBeConstructedWithoutActorIsolation() {
        _ = NotchUserDriver()
    }

    @Test("One click downloads and installs using the new ready callback without a second click")
    func singleClickContinuesThroughInstallation() {
        let manager = UpdateManager()
        var downloadReplies = 0
        var installationReplies = 0
        manager.updateFound(version: "2.0", releaseNotes: nil) { choice in
            #expect(choice == .install)
            downloadReplies += 1
        }
        #expect(downloadReplies == 0)

        manager.performPrimaryAction()
        manager.performPrimaryAction()
        #expect(downloadReplies == 1)
        #expect(manager.state == .downloading(progress: 0))
        #expect(!manager.hasUnseenUpdate)

        manager.downloadStarted(cancellation: {})
        manager.downloadExpectedLength(100)
        manager.downloadReceivedData(100)
        manager.extractionStarted()
        manager.extractionProgress(1)
        manager.readyToInstall { choice in
            #expect(choice == .install)
            installationReplies += 1
            #expect(manager.state == .installing)
        }

        manager.performPrimaryAction()
        #expect(manager.state == .installing)
        #expect(downloadReplies == 1)
        #expect(installationReplies == 1)
    }

    @Test("Sparkle can synchronously complete extraction inside the first install reply")
    func synchronousCallbacksDoNotRestoreTheDownloadState() {
        let manager = UpdateManager()
        var installationReplies = 0
        manager.updateFound(version: "2.0", releaseNotes: nil) { _ in
            manager.downloadStarted(cancellation: {})
            manager.extractionStarted()
            manager.readyToInstall { choice in
                #expect(choice == .install)
                installationReplies += 1
            }
        }

        manager.installUpdate()
        #expect(manager.state == .installing)
        #expect(installationReplies == 1)
    }

    @Test("An already prepared update waits for one user click before restarting")
    func preparedUpdateDoesNotInstallWithoutAUserClick() {
        let manager = UpdateManager()
        var replies = 0
        manager.readyToInstall { choice in
            #expect(choice == .install)
            replies += 1
        }
        #expect(replies == 0)

        manager.performPrimaryAction()
        manager.performPrimaryAction()
        #expect(manager.state == .installing)
        #expect(replies == 1)
    }

    @Test("Cancellation and failure discard the earlier installation request", arguments: [true, false])
    func interruptedUpdateDoesNotRestartLater(cancelled: Bool) {
        let manager = UpdateManager()
        var cancellations = 0
        manager.updateFound(version: "2.0", releaseNotes: nil) { _ in }
        manager.installUpdate()
        manager.downloadStarted { cancellations += 1 }
        if cancelled {
            manager.cancelDownload()
            manager.cancelDownload()
            #expect(cancellations == 1)
        } else {
            manager.updateError("Download failed")
        }

        var replies = 0
        manager.readyToInstall { _ in replies += 1 }
        #expect(replies == 0)
        #expect(manager.state == .readyToInstall(version: "2.0"))
    }

    @Test("A new update offer does not inherit consent from the previous update")
    func newOfferRequiresANewUserClick() {
        let manager = UpdateManager()
        manager.updateFound(version: "2.0", releaseNotes: nil) { _ in }
        manager.installUpdate()

        var replies = 0
        manager.updateFound(version: "2.1", releaseNotes: nil) { _ in replies += 1 }
        manager.readyToInstall { _ in replies += 1 }
        #expect(replies == 0)
        #expect(manager.state == .readyToInstall(version: "2.1"))
    }

    @Test("Finishing an update clears the previous one-click installation request")
    func completedUpdateDoesNotRestartForAnotherPreparedUpdate() {
        let manager = UpdateManager()
        manager.updateFound(version: "2.0", releaseNotes: nil) { _ in }
        manager.installUpdate()
        manager.installed(relaunched: true)

        var replies = 0
        manager.readyToInstall { _ in replies += 1 }
        #expect(replies == 0)
        #expect(manager.state == .readyToInstall(version: "2.0"))
    }

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
