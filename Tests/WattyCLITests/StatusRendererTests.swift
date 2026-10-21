import XCTest
import WattyCore
@testable import WattyCLI

final class StatusRendererTests: XCTestCase {
    private func plainLines(_ report: StatusReport) -> [String] {
        StatusRenderer.lines(for: report, style: .plain)
    }

    func testChargingReportListsEveryReadingInOrder() {
        XCTAssertEqual(plainLines(Fixtures.report()), [
            "Battery        72% · Charging · 1:38 to full",
            "Power source   Power adapter · 70 W rated",
            "System input   59.8 W",
            "System load    30.5 W",
            "Battery power  +29.3 W · charging",
            "Voltage        12.32 V",
            "Amperage       +2.38 A",
            "Battery temp   30.6 °C",
            "Cycles         257",
            "Max capacity   89%",
            "Condition      Normal",
            "Power mode     High Power · Low Power Mode off",
            "SoC temp       55.5 °C",
            "CPU            12.4% · user 8.1% · system 4.3%",
            "Memory         55.3% · 17.7 GB of 32.0 GB"
        ])
    }

    func testOnBatteryReportShowsTimeLeftAndDischargeFlow() {
        let lines = plainLines(Fixtures.report(Fixtures.onBatterySnapshot()))

        XCTAssertEqual(lines[0], "Battery        64% · On battery · 3:35 left")
        XCTAssertEqual(lines[1], "Power source   Battery")
        XCTAssertEqual(lines[4], "Battery power  -11.2 W · discharging")
        XCTAssertEqual(lines[6], "Amperage       -0.91 A")
    }

    func testPluggedInStatesOmitTheTimeEstimate() {
        let charged = plainLines(Fixtures.report(Fixtures.snapshot {
            $0.isCharging = false
            $0.isFullyCharged = true
            $0.level = 100
            $0.batteryPowerWatts = 0
        }))
        let notCharging = plainLines(Fixtures.report(Fixtures.snapshot {
            $0.isCharging = false
            $0.batteryPowerWatts = 0.1
        }))

        XCTAssertEqual(charged[0], "Battery        100% · Charged")
        XCTAssertEqual(charged[4], "Battery power  0.0 W · idle")
        XCTAssertEqual(notCharging[0], "Battery        72% · Plugged in, not charging")
    }

    func testUnknownTimeEstimateIsOmittedRatherThanZero() {
        let lines = plainLines(Fixtures.report(Fixtures.snapshot { $0.timeToFullMinutes = nil }))

        XCTAssertEqual(lines[0], "Battery        72% · Charging")
    }

    func testNoBatteryReportSaysSoAndKeepsPowerModeCPUMemoryAndTemperature() {
        let lines = plainLines(Fixtures.report(Fixtures.noBatterySnapshot()))

        XCTAssertEqual(lines, [
            "Battery     none detected",
            "Power mode  Automatic · Low Power Mode off",
            "SoC temp    55.5 °C",
            "CPU         12.4% · user 8.1% · system 4.3%",
            "Memory      55.3% · 17.7 GB of 32.0 GB"
        ])
    }

    func testUnknownValuesPrintAsDashesNeverZeros() {
        let report = Fixtures.report(
            Fixtures.snapshot {
                $0.voltageVolts = nil
                $0.amperageAmps = nil
                $0.batteryPowerWatts = nil
                $0.systemPowerWatts = nil
                $0.systemLoadWatts = nil
                $0.adapterRatedWatts = nil
                $0.cycleCount = nil
                $0.condition = nil
                $0.maximumCapacityPercent = nil
                $0.temperatureCelsius = nil
                $0.timeToFullMinutes = nil
                $0.powerMode = nil
                $0.lowPowerModeActive = nil
            },
            stats: Fixtures.stats(cpu: nil, memory: nil, temperature: nil)
        )

        let lines = plainLines(report)
        let valuesByKey = Dictionary(uniqueKeysWithValues: lines.map { line -> (String, String) in
            let key = String(line.prefix(14)).trimmingCharacters(in: .whitespaces)
            return (key, String(line.dropFirst(15)))
        })

        for key in ["System input", "System load", "Battery power", "Voltage", "Amperage", "Battery temp",
                    "Cycles", "Max capacity", "Condition", "Power mode", "SoC temp", "CPU", "Memory"] {
            XCTAssertEqual(valuesByKey[key], "—", key)
        }
        XCTAssertEqual(valuesByKey["Power source"], "Power adapter")
    }

    func testValuesStartInTheSameColumn() {
        for line in plainLines(Fixtures.report()) {
            let characters = Array(line)
            XCTAssertEqual(characters[14], " ", line)
            XCTAssertNotEqual(characters[15], " ", line)
        }
    }

    func testPlainStyleEmitsNoEscapeSequences() {
        for line in plainLines(Fixtures.report()) {
            XCTAssertFalse(line.contains("\u{1B}"), line)
        }
    }

    func testStyledOutputOnlyAddsEscapeSequences() {
        let report = Fixtures.report()

        let styled = StatusRenderer.lines(for: report, style: TextStyle(isEnabled: true))

        XCTAssertEqual(styled.map(stripANSI), plainLines(report))
        XCTAssertTrue(styled[0].contains("\u{1B}[1mBattery\u{1B}[0m"))
        XCTAssertTrue(styled[0].contains("\u{1B}[32m72%\u{1B}[0m"))
    }

    func testLowBatteryOnBatteryUsesWarningColors() {
        let critical = StatusRenderer.lines(for: Fixtures.report(Fixtures.onBatterySnapshot(level: 8)), style: TextStyle(isEnabled: true))
        let low = StatusRenderer.lines(for: Fixtures.report(Fixtures.onBatterySnapshot(level: 15)), style: TextStyle(isEnabled: true))
        let healthy = StatusRenderer.lines(for: Fixtures.report(Fixtures.onBatterySnapshot(level: 64)), style: TextStyle(isEnabled: true))

        XCTAssertTrue(critical[0].contains("\u{1B}[31m8%"))
        XCTAssertTrue(low[0].contains("\u{1B}[33m15%"))
        XCTAssertFalse(healthy[0].contains("\u{1B}[3"))
    }

    func testServiceRecommendedConditionIsHighlighted() {
        let report = Fixtures.report(Fixtures.snapshot { $0.condition = "Service Recommended" })

        let styled = StatusRenderer.lines(for: report, style: TextStyle(isEnabled: true))

        XCTAssertTrue(styled.contains { $0.contains("\u{1B}[33mService Recommended\u{1B}[0m") })
    }

    func testSwapIsShownOnlyWhenInUse() {
        let swapping = MemoryUsage(
            usedBytes: 40_000_000_000,
            appBytes: 30_000_000_000,
            wiredBytes: 5_000_000_000,
            compressedBytes: 5_000_000_000,
            totalBytes: 68_719_476_736,
            swapUsedBytes: 2_089_877_504
        )

        let lines = plainLines(Fixtures.report(stats: Fixtures.stats(memory: swapping)))

        XCTAssertEqual(lines.last, "Memory         58.2% · 37.3 GB of 64.0 GB · swap 1.95 GB")
    }

    func testWorstCaseLinesFitIn80Columns() {
        let report = Fixtures.report(
            Fixtures.snapshot {
                $0.level = 100
                $0.isCharging = false
                $0.powerSource = .adapter
                $0.adapterRatedWatts = 240
                $0.batteryPowerWatts = -123.45
                $0.systemPowerWatts = 240.5
                $0.condition = "Service Recommended"
                $0.powerMode = .lowPower
            },
            stats: Fixtures.stats(
                cpu: CPUUsage(userPercent: 55.55, systemPercent: 44.44),
                memory: MemoryUsage(
                    usedBytes: 500_000_000_000,
                    appBytes: 400_000_000_000,
                    wiredBytes: 50_000_000_000,
                    compressedBytes: 50_000_000_000,
                    totalBytes: 549_755_813_888,
                    swapUsedBytes: 120_000_000_000
                )
            )
        )

        for line in plainLines(report) {
            XCTAssertLessThanOrEqual(line.count, 80, line)
        }
    }
}
