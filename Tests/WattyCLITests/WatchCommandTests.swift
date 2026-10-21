import XCTest
import WattyCore
@testable import WattyCLI

final class WatchCommandTests: XCTestCase {
    func testWatchPrintsOneCompactLinePerSampleWhenPiped() async {
        let rig = TestRig(allowedSleeps: 2)

        let code = await rig.run("watch", "--interval", "3")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.outputLines, Array(
            repeating: "2026-10-21T18:04:04+02:00 level=72 state=charging battery_w=+29.3 system_w=30.5",
            count: 3
        ))
        XCTAssertEqual(rig.sleeper.durations, [3, 3, 3])
        XCTAssertEqual(rig.telemetry.snapshotCalls, 3)
        XCTAssertEqual(rig.telemetry.statsCalls, 0)
        XCTAssertFalse(rig.console.output.contains("\u{1B}"))
    }

    func testWatchSubtractsTheTimeSpentSamplingFromTheWait() async {
        let clock = SteppingClock(step: 0.4)
        let sleeper = SleepRecorder(allowedSleeps: 1)
        let console = CapturingConsole()
        let context = CommandContext(
            telemetry: StubTelemetry(),
            console: console,
            terminal: TerminalEnvironment(isInteractive: false),
            launcher: StubLauncher(),
            now: clock.now,
            sleep: sleeper.sleep
        )

        _ = await CommandLineTool.run(arguments: ["watch", "--interval", "2"], context: context)

        XCTAssertEqual(sleeper.durations.count, 2)
        XCTAssertEqual(sleeper.durations[0], 2 - 0.4, accuracy: 0.0001)
    }

    func testWatchReportsEachDistinctWarningOnlyOnce() async {
        let snapshot = Fixtures.snapshot { $0.warnings = ["ioreg battery read failed"] }
        let rig = TestRig(telemetry: StubTelemetry(snapshot: snapshot), allowedSleeps: 2)

        _ = await rig.run("watch")

        XCTAssertEqual(rig.console.errors, "watty: warning: ioreg battery read failed\n")
        XCTAssertEqual(rig.console.outputLines.count, 3)
    }

    func testWatchWithoutABatteryStillPrintsLines() async {
        let rig = TestRig(telemetry: StubTelemetry(snapshot: Fixtures.noBatterySnapshot()), allowedSleeps: 0)

        _ = await rig.run("watch")

        XCTAssertEqual(rig.console.outputLines, ["2026-10-21T18:04:04+02:00 level=— state=no_battery battery_w=— system_w=—"])
    }

    func testWatchRedrawsInPlaceOnATerminalAndRestoresItWhenDone() async {
        let terminal = TerminalEnvironment(isInteractive: true, term: "xterm-256color")
        let rig = TestRig(terminal: terminal, allowedSleeps: 3)

        let code = await rig.run("watch", "--interval", "2")

        XCTAssertEqual(code, 0)
        let output = rig.console.output
        XCTAssertTrue(output.hasPrefix("\u{1B}[?1049h\u{1B}[?25l"))
        XCTAssertTrue(output.hasSuffix("\u{1B}[?25h\u{1B}[?1049l"))
        XCTAssertEqual(output.components(separatedBy: "\u{1B}[H").count - 1, 3)
        XCTAssertTrue(output.contains("Battery"))
        XCTAssertEqual(rig.sleeper.durations.first, CLIDefaults.cpuSamplingWindow)
        XCTAssertEqual(rig.telemetry.statsCalls, 4)
        XCTAssertEqual(rig.console.errors, "")
    }

    func testWatchFramesShowWarningsInsideTheScreen() async {
        let snapshot = Fixtures.snapshot { $0.warnings = ["ioreg battery read failed"] }
        let terminal = TerminalEnvironment(isInteractive: true, term: "xterm-256color")
        let rig = TestRig(telemetry: StubTelemetry(snapshot: snapshot), terminal: terminal, allowedSleeps: 1)

        _ = await rig.run("watch")

        XCTAssertTrue(stripANSI(rig.console.output).contains("warning: ioreg battery read failed"))
        XCTAssertEqual(rig.console.errors, "")
    }

    func testWatchOnADumbTerminalFallsBackToLines() async {
        let terminal = TerminalEnvironment(isInteractive: true, term: "dumb")
        let rig = TestRig(terminal: terminal, allowedSleeps: 1)

        _ = await rig.run("watch")

        XCTAssertFalse(rig.console.output.contains("\u{1B}"))
        XCTAssertEqual(rig.console.outputLines.count, 2)
    }
}

final class SteppingClock {
    private let step: TimeInterval
    private var calls = 0

    init(step: TimeInterval) {
        self.step = step
    }

    func now() -> Date {
        defer { calls += 1 }
        return Fixtures.date.addingTimeInterval(Double(calls) * step)
    }
}
