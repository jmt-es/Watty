import XCTest
@testable import Watty
import WattyCore

final class LaunchOptionsTests: XCTestCase {
    func testNoArgumentsMeansNormalLaunch() throws {
        let options = try LaunchOptions.parse([])
        XCTAssertNil(options.capture)
        XCTAssertNil(options.appearance)
        XCTAssertFalse(options.isCapturing)
    }

    func testCapturePanelWithAppearance() throws {
        let options = try LaunchOptions.parse(["--capture-panel", "/tmp/panel.png", "--appearance", "dark"])
        XCTAssertEqual(options.capture?.target, .panel)
        XCTAssertEqual(options.capture?.outputURL.path, "/tmp/panel.png")
        XCTAssertEqual(options.appearance, .dark)
        XCTAssertTrue(options.isCapturing)
    }

    func testCaptureSettingsWithEqualsSyntax() throws {
        let options = try LaunchOptions.parse(["--capture-settings=/tmp/settings.png", "--appearance=light"])
        XCTAssertEqual(options.capture?.target, .settings)
        XCTAssertEqual(options.appearance, .light)
    }

    func testTildeAndRelativePathsAreResolved() throws {
        let home = try LaunchOptions.parse(["--capture-panel", "~/shots/p.png"])
        XCTAssertEqual(home.capture?.outputURL.path, NSHomeDirectory() + "/shots/p.png")
        let relative = try LaunchOptions.parse(["--capture-panel", "out.png"])
        XCTAssertEqual(relative.capture?.outputURL.lastPathComponent, "out.png")
        XCTAssertTrue(relative.capture?.outputURL.path.hasPrefix("/") ?? false)
    }

    func testAppKitArgumentsAreIgnored() throws {
        let options = try LaunchOptions.parse(["-NSDocumentRevisionsDebugMode", "YES", "-AppleLanguages", "(es)", "--capture-panel", "/tmp/a.png"])
        XCTAssertEqual(options.capture?.outputURL.path, "/tmp/a.png")
    }

    func testMissingValueIsAnError() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .missingValue("--capture-panel")) }
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "--appearance", "dark"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .missingValue("--capture-panel")) }
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-settings", "/tmp/a.png", "--appearance"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .missingValue("--appearance")) }
    }

    func testInvalidAppearanceIsAnError() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--appearance", "purple"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .invalidAppearance("purple")) }
    }

    func testOutputMustBeAPNG() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/.zshrc"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .outputIsNotPNG("/tmp/.zshrc")) }
        XCTAssertNoThrow(try LaunchOptions.parse(["--capture-panel", "/tmp/Shot.PNG"]))
    }

    func testBothCaptureTargetsConflict() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--capture-settings", "/tmp/b.png"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .conflictingCaptures)
        }
    }

    func testHistoryFileNeedsACapture() throws {
        XCTAssertThrowsError(try LaunchOptions.parse(["--history-file", "/tmp/h.json"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .historyFileWithoutCapture) }
        let options = try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--history-file", "/tmp/h.json"])
        XCTAssertEqual(options.historyFileURL?.path, "/tmp/h.json")
    }

    func testNoDemoByDefault() throws {
        XCTAssertNil(try LaunchOptions.parse([]).demoScenario)
        XCTAssertNil(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png"]).demoScenario)
    }

    func testDemoWithACaptureUsesTheChargingScenario() throws {
        let panel = try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo"])
        let settings = try LaunchOptions.parse(["--demo", "--capture-settings", "/tmp/b.png"])

        XCTAssertEqual(panel.demoScenario, .charging)
        XCTAssertEqual(settings.demoScenario, .charging)
        XCTAssertEqual(DemoScenario.default, .charging)
    }

    func testEveryDemoScenarioCanBeRequested() throws {
        for scenario in DemoScenario.allCases {
            let separate = try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo", "--demo-scenario", scenario.rawValue])
            let inline = try LaunchOptions.parse(["--capture-panel=/tmp/a.png", "--demo", "--demo-scenario=\(scenario.rawValue)"])

            XCTAssertEqual(separate.demoScenario, scenario)
            XCTAssertEqual(inline.demoScenario, scenario)
        }
    }

    func testDemoArgumentsCoexistWithAppearanceAndAppKitArguments() throws {
        let options = try LaunchOptions.parse([
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--capture-panel", "/tmp/a.png", "--appearance", "dark", "--demo", "--demo-scenario", "battery"
        ])

        XCTAssertEqual(options.demoScenario, .battery)
        XCTAssertEqual(options.appearance, .dark)
        XCTAssertEqual(options.capture?.target, .panel)
    }

    func testDemoNeedsACapture() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--demo"])) { XCTAssertEqual($0 as? LaunchOptions.ParseError, .demoWithoutCapture) }
        XCTAssertThrowsError(try LaunchOptions.parse(["--demo", "--appearance", "dark"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .demoWithoutCapture)
        }
    }

    func testDemoScenarioNeedsDemo() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--demo-scenario", "battery"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .demoScenarioWithoutDemo)
        }
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo-scenario", "battery"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .demoScenarioWithoutDemo)
        }
    }

    func testUnknownDemoScenarioIsAnError() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo", "--demo-scenario", "tablet"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .invalidDemoScenario("tablet"))
        }
    }

    func testDemoScenarioNeedsAValue() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo", "--demo-scenario"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .missingValue("--demo-scenario"))
        }
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo", "--demo-scenario", "--appearance", "dark"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .missingValue("--demo-scenario"))
        }
    }

    func testDemoIsAFlagAndTakesNoValue() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo=false"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .unexpectedValue("--demo"))
        }
    }

    func testDemoCannotBeCombinedWithAHistoryFile() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--capture-panel", "/tmp/a.png", "--demo", "--history-file", "/tmp/h.json"])) {
            XCTAssertEqual($0 as? LaunchOptions.ParseError, .demoWithHistoryFile)
        }
    }

    func testDemoErrorsExplainWhatToDo() {
        let messages = [
            LaunchOptions.ParseError.demoWithoutCapture,
            .demoScenarioWithoutDemo,
            .demoWithHistoryFile,
            .invalidDemoScenario("tablet"),
            .unexpectedValue("--demo")
        ].compactMap(\.errorDescription)

        XCTAssertEqual(messages, [
            "--demo only works together with --capture-panel or --capture-settings",
            "--demo-scenario needs --demo",
            "--demo provides its own history, so it cannot be combined with --history-file",
            "--demo-scenario must be one of charging, battery, desktop, not tablet",
            "--demo does not take a value"
        ])
    }

    func testWattyURLsAreNotArguments() throws {
        let options = try LaunchOptions.parse(["watty://capture?path=/etc/passwd"])
        XCTAssertNil(options.capture)
    }
}
