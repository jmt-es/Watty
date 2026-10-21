import XCTest
import WattyCore
@testable import WattyCLI

final class ShowCommandTests: XCTestCase {
    func testShowPostsTheNotificationWhenTheAppIsRunning() async {
        let rig = TestRig()
        rig.launcher.running = true

        let code = await rig.run("show")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.launcher.events, ["isRunning com.jmtes.watty", "post"])
        XCTAssertEqual(rig.console.output, "")
        XCTAssertEqual(rig.console.errors, "")
    }

    func testShowLaunchesTheAppThenAsksForThePanelWhenItIsNotRunning() async {
        let rig = TestRig()

        let code = await rig.run("show")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.launcher.events, [
            "isRunning com.jmtes.watty",
            "lookup com.jmtes.watty",
            "launch /Applications/Watty.app",
            "wait 10",
            "post"
        ])
    }

    func testShowExplainsHowToInstallWhenTheAppIsMissing() async {
        let rig = TestRig()
        rig.launcher.installedURL = nil

        let code = await rig.run("show")

        XCTAssertEqual(code, 1)
        XCTAssertEqual(rig.console.output, "")
        XCTAssertTrue(rig.console.errors.hasPrefix("watty: Watty.app is not installed"))
        XCTAssertTrue(rig.console.errors.contains("com.jmtes.watty"))
        XCTAssertTrue(rig.console.errors.contains("brew install jmt-es/tap/watty"))
        XCTAssertFalse(rig.launcher.events.contains { $0.hasPrefix("launch") })
        XCTAssertFalse(rig.launcher.events.contains("post"))
    }

    func testShowReportsLaunchFailures() async {
        struct LaunchFailure: LocalizedError {
            var errorDescription: String? { "the application is damaged" }
        }
        let rig = TestRig()
        rig.launcher.launchError = LaunchFailure()

        let code = await rig.run("show")

        XCTAssertEqual(code, 1)
        XCTAssertEqual(rig.console.errors, "watty: could not open /Applications/Watty.app: the application is damaged\n")
        XCTAssertFalse(rig.launcher.events.contains("post"))
    }

    func testShowFailsWhenTheLaunchedAppNeverBecomesReady() async {
        let rig = TestRig()
        rig.launcher.becomesReady = false

        let code = await rig.run("show")

        XCTAssertEqual(code, 1)
        XCTAssertTrue(rig.console.errors.contains("did not finish launching within 10 s"))
        XCTAssertFalse(rig.launcher.events.contains("post"))
    }
}
