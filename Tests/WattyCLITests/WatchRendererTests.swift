import XCTest
import WattyCore
@testable import WattyCLI

final class WatchRendererTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0) ?? .current
    private let madrid = TimeZone(secondsFromGMT: 7200) ?? .current

    func testLineCarriesTimeLevelStateAndPowerFlow() {
        let line = WatchRenderer.line(report: Fixtures.report(), date: Fixtures.date, timeZone: madrid)

        XCTAssertEqual(line, "2026-10-21T18:04:04+02:00 level=72 state=charging battery_w=+29.3 system_w=30.5 net_flow=—")
    }

    func testLineUsesZForUTC() {
        let line = WatchRenderer.line(report: Fixtures.report(), date: Fixtures.date, timeZone: utc)

        XCTAssertTrue(line.hasPrefix("2026-10-21T16:04:04Z "), line)
    }

    func testLineStatesFollowTheJSONIdentifiers() {
        let onBattery = WatchRenderer.line(report: Fixtures.report(Fixtures.onBatterySnapshot()), date: Fixtures.date, timeZone: utc)
        let notCharging = WatchRenderer.line(
            report: Fixtures.report(Fixtures.snapshot { $0.isCharging = false }),
            date: Fixtures.date,
            timeZone: utc
        )

        XCTAssertTrue(onBattery.contains("state=on_battery battery_w=-11.2"), onBattery)
        XCTAssertTrue(notCharging.contains("state=plugged_in_not_charging"), notCharging)
    }

    func testLineUsesDashesForUnknownValues() {
        let report = Fixtures.report(Fixtures.snapshot {
            $0.batteryPowerWatts = nil
            $0.systemLoadWatts = nil
            $0.systemPowerWatts = nil
        })

        let line = WatchRenderer.line(report: report, date: Fixtures.date, timeZone: utc)

        XCTAssertTrue(line.hasSuffix("battery_w=— system_w=— net_flow=—"), line)
    }

    func testLineWithoutBatteryNamesTheCondition() {
        let line = WatchRenderer.line(report: Fixtures.report(Fixtures.noBatterySnapshot()), date: Fixtures.date, timeZone: utc)

        XCTAssertEqual(line, "2026-10-21T16:04:04Z level=— state=no_battery battery_w=— system_w=— net_flow=—")
    }

    func testLineCarriesTheNetFlowAsTheLastField() {
        let draining = Fixtures.report(Fixtures.drainingSnapshot { $0.batteryPowerWatts = 4.8 })
        let onBattery = Fixtures.report(Fixtures.onBatterySnapshot { $0.netFlow = NetFlowEstimate(flow: .draining) })
        let holding = Fixtures.report(Fixtures.snapshot {
            $0.isCharging = false
            $0.netFlow = NetFlowEstimate(flow: .holding)
        })

        XCTAssertTrue(WatchRenderer.line(report: draining, date: Fixtures.date, timeZone: utc).hasSuffix("state=charging battery_w=+4.8 system_w=38.0 net_flow=draining"))
        XCTAssertTrue(WatchRenderer.line(report: onBattery, date: Fixtures.date, timeZone: utc).hasSuffix("net_flow=draining"))
        XCTAssertTrue(WatchRenderer.line(report: holding, date: Fixtures.date, timeZone: utc).hasSuffix("net_flow=holding"))
    }

    func testLineIsASingleCompactLine() {
        let line = WatchRenderer.line(report: Fixtures.report(), date: Fixtures.date, timeZone: madrid)

        XCTAssertFalse(line.contains("\n"))
        XCTAssertLessThanOrEqual(line.count, 90)
    }

    func testFrameStartsWithATitleAndThenTheStatusRows() {
        let report = Fixtures.report()

        let frame = WatchRenderer.frame(report: report, interval: 2, date: Fixtures.date, style: .plain)

        XCTAssertTrue(frame[0].hasPrefix("Watty \(report.wattyVersion) · every 2 s · "), frame[0])
        XCTAssertTrue(frame[0].hasSuffix(" · Ctrl-C to quit"), frame[0])
        XCTAssertEqual(frame[1], "")
        XCTAssertEqual(Array(frame.dropFirst(2)), StatusRenderer.lines(for: report, style: .plain))
    }

    func testFrameShowsWarningsInsteadOfWritingToTheScreenBehindIt() {
        let report = Fixtures.report(Fixtures.snapshot { $0.warnings = ["ioreg battery read failed"] })

        let frame = WatchRenderer.frame(report: report, interval: 2, date: Fixtures.date, style: .plain)

        XCTAssertEqual(frame.suffix(2), ["", "warning: ioreg battery read failed"])
    }
}
