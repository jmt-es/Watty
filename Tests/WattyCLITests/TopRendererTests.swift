import XCTest
import WattyCore
@testable import WattyCLI

final class TopRendererTests: XCTestCase {
    private let consumers = [
        Fixtures.consumer("Google Chrome", cpu: 116.94, memory: 3_458_000_000),
        Fixtures.consumer("WindowServer", cpu: 51.6, memory: 0),
        Fixtures.consumer("Slack", cpu: 4.04, memory: 387_927_040)
    ]

    func testTableAlignsColumnsAndMarksUnknownMemory() {
        let report = Fixtures.topReport(consumers)

        let lines = TopRenderer.lines(for: report, columns: 80, style: .plain)

        XCTAssertEqual(lines, [
            "Top apps by CPU · averaged over 1 s",
            "    CPU     MEMORY  APP",
            " 116.9%    3.22 GB  Google Chrome",
            "  51.6%          —  WindowServer",
            "   4.0%     370 MB  Slack"
        ])
    }

    func testLimitIsAppliedByTheReport() {
        let report = Fixtures.topReport(consumers, limit: 2)

        let lines = TopRenderer.lines(for: report, columns: 80, style: .plain)

        XCTAssertEqual(lines.count, 4)
        XCTAssertFalse(lines.joined().contains("Slack"))
    }

    func testLongNamesAreTruncatedToTheTerminalWidth() {
        let report = Fixtures.topReport([
            Fixtures.consumer("A very long application name that would wrap the line", cpu: 10, memory: 1_000_000)
        ])

        let lines = TopRenderer.lines(for: report, columns: 50, style: .plain)

        XCTAssertLessThanOrEqual(lines[2].count, 50)
        XCTAssertTrue(lines[2].hasSuffix("…"))
    }

    func testNamesAreNeverTruncatedWhenThereIsNoTerminalWidth() {
        let name = "A very long application name that would wrap the line on any terminal at all"
        let report = Fixtures.topReport([Fixtures.consumer(name, cpu: 10, memory: 1_000_000)])

        let lines = TopRenderer.lines(for: report, columns: nil, style: .plain)

        XCTAssertTrue(lines[2].hasSuffix(name))
    }

    func testVeryNarrowTerminalsKeepAReadableNameColumn() {
        let report = Fixtures.topReport([Fixtures.consumer("Visual Studio Code", cpu: 10, memory: 1_000_000)])

        let lines = TopRenderer.lines(for: report, columns: 10, style: .plain)

        XCTAssertTrue(lines[2].hasSuffix("Visual Stud…"), lines[2])
    }

    func testEmptyReportExplainsTheThreshold() {
        let lines = TopRenderer.lines(for: Fixtures.topReport([]), columns: 80, style: .plain)

        XCTAssertEqual(lines, ["Top apps by CPU · averaged over 1 s", "No app is using more than 0.2% CPU."])
    }

    func testStyledTableOnlyAddsEscapeSequences() {
        let report = Fixtures.topReport(consumers)

        let styled = TopRenderer.lines(for: report, columns: 80, style: TextStyle(isEnabled: true))
        let plain = TopRenderer.lines(for: report, columns: 80, style: .plain)

        XCTAssertEqual(styled.map(stripANSI), plain)
        XCTAssertTrue(styled[1].contains("\u{1B}[1m"))
    }

    func testIntervalCaptionFollowsTheRequestedInterval() {
        let lines = TopRenderer.lines(for: Fixtures.topReport(consumers, interval: 0.5), columns: 80, style: .plain)

        XCTAssertEqual(lines[0], "Top apps by CPU · averaged over 0.5 s")
    }
}
