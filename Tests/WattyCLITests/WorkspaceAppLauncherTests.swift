import XCTest
@testable import WattyCLI

final class WorkspaceAppLauncherTests: XCTestCase {
    private let unknownBundleIdentifier = "com.jmtes.watty.tests.not-installed"

    func testAnUnknownApplicationIsNotRunning() {
        XCTAssertFalse(WorkspaceAppLauncher().isRunning(bundleIdentifier: unknownBundleIdentifier))
    }

    func testAnUnknownApplicationHasNoURL() {
        XCTAssertNil(WorkspaceAppLauncher().applicationURL(bundleIdentifier: unknownBundleIdentifier))
    }

    func testAnInstalledApplicationIsFoundByBundleIdentifier() {
        let url = WorkspaceAppLauncher().applicationURL(bundleIdentifier: "com.apple.finder")

        XCTAssertEqual(url?.lastPathComponent, "Finder.app")
    }

    func testWaitingForAnApplicationThatNeverStartsTimesOut() async {
        let ready = await WorkspaceAppLauncher().waitUntilReady(bundleIdentifier: unknownBundleIdentifier, timeout: 0.3)

        XCTAssertFalse(ready)
    }

    func testTheShowNotificationNameIsTheOneTheAppObserves() {
        XCTAssertEqual(WorkspaceAppLauncher.showNotificationName, "com.jmtes.watty.show")
    }
}
