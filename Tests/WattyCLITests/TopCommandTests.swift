import XCTest
import WattyCore
@testable import WattyCLI

final class TopCommandTests: XCTestCase {
    func testTopSamplesTwiceAcrossTheInterval() async {
        let rig = TestRig()

        let code = await rig.run("top", "--interval", "2")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.telemetry.energyCalls, 2)
        XCTAssertEqual(rig.sleeper.durations, [2])
        XCTAssertEqual(rig.console.outputLines, [
            "Top apps by CPU · averaged over 2 s",
            "    CPU     MEMORY  APP",
            "  41.3%    1.86 GB  Chrome",
            "  12.3%          —  WindowServer",
            "   4.0%     858 MB  Slack"
        ])
        XCTAssertEqual(rig.console.errors, "")
    }

    func testTopAppliesTheLimit() async {
        let rig = TestRig()

        _ = await rig.run("top", "--limit", "1")

        XCTAssertEqual(rig.console.outputLines.count, 3)
        XCTAssertTrue(rig.console.output.contains("Chrome"))
        XCTAssertFalse(rig.console.output.contains("Slack"))
    }

    func testTopJSON() async throws {
        let rig = TestRig()

        let code = await rig.run("top", "--json", "--limit", "2")

        XCTAssertEqual(code, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rig.console.output.utf8)) as? [String: Any])
        let rows = try XCTUnwrap(object["consumers"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["name"] as? String }, ["Chrome", "WindowServer"])
        XCTAssertTrue(rows[1]["memory_bytes"] is NSNull)
        XCTAssertEqual(object["interval_seconds"] as? Double, 1)
        XCTAssertEqual(object["schema_version"] as? Int, 1)
    }

    func testTopFailsClearlyWhenTheSamplerHasNoData() async {
        let telemetry = StubTelemetry(energySamples: [Fixtures.energySample([], warmingUp: true)])
        let rig = TestRig(telemetry: telemetry)

        let code = await rig.run("top")

        XCTAssertEqual(code, 1)
        XCTAssertEqual(rig.console.output, "")
        XCTAssertEqual(rig.console.errors, "watty: could not sample the running processes (the sampler returned no data)\n")
    }

    func testTopFailsWhenTheSamplerReportsFailure() async {
        let telemetry = StubTelemetry(energySamples: [Fixtures.energySample([], failed: true)])
        let rig = TestRig(telemetry: telemetry)

        let code = await rig.run("top", "--json")

        XCTAssertEqual(code, 1)
        XCTAssertEqual(rig.console.output, "")
    }

    func testTopTruncatesNamesOnlyOnATerminal() async {
        let longName = "A very long process name that is wider than any reasonable terminal column"
        let sample = Fixtures.energySample([Fixtures.consumer(longName, cpu: 10, memory: 1_000_000)])
        let samples = [Fixtures.energySample([], warmingUp: true), sample]
        let piped = TestRig(telemetry: StubTelemetry(energySamples: samples))
        let terminal = TestRig(
            telemetry: StubTelemetry(energySamples: samples),
            terminal: TerminalEnvironment(isInteractive: true, term: "xterm", colorDisabled: true, columns: 50)
        )

        _ = await piped.run("top")
        _ = await terminal.run("top")

        XCTAssertTrue(piped.console.output.contains(longName))
        XCTAssertFalse(terminal.console.output.contains(longName))
        XCTAssertTrue(terminal.console.outputLines.allSatisfy { $0.count <= 50 })
    }

    func testTopWithNothingAboveTheThresholdSaysSo() async {
        let telemetry = StubTelemetry(energySamples: [Fixtures.energySample([], warmingUp: true), Fixtures.energySample([])])
        let rig = TestRig(telemetry: telemetry)

        let code = await rig.run("top")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.outputLines.last, "No app is using more than 0.2% CPU.")
    }
}
