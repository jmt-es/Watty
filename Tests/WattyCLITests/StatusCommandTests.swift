import XCTest
import WattyCore
@testable import WattyCLI

final class StatusCommandTests: XCTestCase {
    func testStatusPrintsTheHumanReportAfterMeasuringCPUOverAWindow() async {
        let rig = TestRig()

        let code = await rig.run("status")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.errors, "")
        XCTAssertEqual(rig.console.outputLines.first, "Battery        72% · Charging · 1:38 to full")
        XCTAssertEqual(rig.console.outputLines.last, "Memory         55.3% · 17.7 GB of 32.0 GB")
        XCTAssertEqual(rig.console.outputLines.count, 15)
        XCTAssertEqual(rig.telemetry.snapshotCalls, 1)
        XCTAssertEqual(rig.telemetry.statsCalls, 2)
        XCTAssertEqual(rig.sleeper.durations, [CLIDefaults.cpuSamplingWindow])
    }

    func testNoArgumentsBehavesLikeStatus() async {
        let bare = TestRig()
        let explicit = TestRig()

        let bareCode = await bare.run()
        let explicitCode = await explicit.run("status")

        XCTAssertEqual(bareCode, 0)
        XCTAssertEqual(explicitCode, 0)
        XCTAssertEqual(bare.console.output, explicit.console.output)
    }

    func testStatusJSONIsADocumentedReportOnStdoutOnly() async throws {
        let rig = TestRig()

        let code = await rig.run("status", "--json")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.errors, "")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rig.console.output.utf8)) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["has_battery"] as? Bool, true)
        XCTAssertEqual(object["timestamp"] as? String, "2026-10-21T16:04:04Z")
        XCTAssertEqual((object["battery"] as? [String: Any])?["level_percent"] as? Int, 72)
        XCTAssertTrue(rig.console.output.hasSuffix("}\n"))
    }

    func testStatusJSONWithoutABatteryHasNullBatteryFields() async throws {
        let rig = TestRig(telemetry: StubTelemetry(snapshot: Fixtures.noBatterySnapshot()))

        let code = await rig.run("status", "--json")

        XCTAssertEqual(code, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rig.console.output.utf8)) as? [String: Any])
        let battery = try XCTUnwrap(object["battery"] as? [String: Any])
        XCTAssertEqual(object["has_battery"] as? Bool, false)
        XCTAssertTrue(battery.values.allSatisfy { $0 is NSNull })
        XCTAssertEqual((object["power"] as? [String: Any])?["mode"] as? String, "automatic")
    }

    func testStatusWithoutABatterySaysSoAndStillShowsTheRest() async {
        let rig = TestRig(telemetry: StubTelemetry(snapshot: Fixtures.noBatterySnapshot()))

        let code = await rig.run("status")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.outputLines.first, "Battery     none detected")
        XCTAssertTrue(rig.console.output.contains("Power mode  Automatic"))
        XCTAssertTrue(rig.console.output.contains("CPU         12.4%"))
        XCTAssertTrue(rig.console.output.contains("Memory      55.3%"))
        XCTAssertTrue(rig.console.output.contains("SoC temp    55.5 °C"))
    }

    func testSnapshotWarningsGoToStderrWithoutTouchingStdout() async {
        let snapshot = Fixtures.snapshot { $0.warnings = ["system_profiler detail read failed"] }
        let rig = TestRig(telemetry: StubTelemetry(snapshot: snapshot))

        let code = await rig.run("status")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.errors, "watty: warning: system_profiler detail read failed\n")
        XCTAssertFalse(rig.console.output.contains("warning"))
    }

    func testInteractiveTerminalGetsStyledTextButNeverStyledJSON() async {
        let terminal = TerminalEnvironment(isInteractive: true, term: "xterm-256color")
        let text = TestRig(terminal: terminal)
        let json = TestRig(terminal: terminal)

        _ = await text.run("status")
        _ = await json.run("status", "--json")

        XCTAssertTrue(text.console.output.contains("\u{1B}[1mBattery\u{1B}[0m"))
        XCTAssertFalse(json.console.output.contains("\u{1B}"))
    }

    func testNoColorKeepsTheInteractiveOutputPlain() async {
        let rig = TestRig(terminal: TerminalEnvironment(isInteractive: true, term: "xterm", colorDisabled: true))

        _ = await rig.run("status")

        XCTAssertFalse(rig.console.output.contains("\u{1B}"))
    }
}
