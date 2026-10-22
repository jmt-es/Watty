import XCTest
@testable import Watty
import WattyCore

final class DemoStatsTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    func testHistoryCoversTheLastTenMinutesEveryTwoSeconds() throws {
        for scenario in DemoScenario.allCases {
            let history = DemoStats.history(for: scenario, endingAt: end)

            XCTAssertEqual(history.count, 301, "\(scenario)")
            XCTAssertEqual(try XCTUnwrap(history.first).date, end.addingTimeInterval(-RefreshCadence.statsWindow), "\(scenario)")
            XCTAssertEqual(try XCTUnwrap(history.last).date, end, "\(scenario)")
            XCTAssertLessThanOrEqual(history.count, RefreshCadence.statsLimit)
            for (previous, next) in zip(history, history.dropFirst()) {
                XCTAssertEqual(next.date.timeIntervalSince(previous.date), DemoStats.historyInterval, accuracy: 0.001)
            }
        }
    }

    func testHistoryIsDeterministic() {
        for scenario in DemoScenario.allCases {
            XCTAssertEqual(
                DemoStats.history(for: scenario, endingAt: end),
                DemoStats.history(for: scenario, endingAt: end)
            )
        }
    }

    func testHistoryEndsExactlyOnTheCurrentReading() throws {
        for scenario in DemoScenario.allCases {
            let latest = try XCTUnwrap(DemoStats.history(for: scenario, endingAt: end).last)

            XCTAssertEqual(latest, DemoStats.current(for: scenario, at: end), "\(scenario)")
        }
    }

    func testChartsHaveSomethingToDraw() throws {
        let history = DemoStats.history(for: .charging, endingAt: end)
        let cpu = try history.map { try XCTUnwrap($0.cpu).totalPercent }
        let memory = try history.map { try XCTUnwrap($0.memory).usedPercent }

        XCTAssertGreaterThan((cpu.max() ?? 0) - (cpu.min() ?? 0), 8)
        XCTAssertGreaterThan((memory.max() ?? 0) - (memory.min() ?? 0), 0.5)
    }

    func testEverySampleIsPlausible() throws {
        for scenario in DemoScenario.allCases {
            for sample in DemoStats.history(for: scenario, endingAt: end) {
                let cpu = try XCTUnwrap(sample.cpu)
                let memory = try XCTUnwrap(sample.memory)
                let temperature = try XCTUnwrap(sample.temperature)

                XCTAssertTrue((0...100).contains(cpu.totalPercent), "\(scenario) cpu \(cpu.totalPercent)")
                XCTAssertGreaterThan(cpu.userPercent, cpu.systemPercent)
                XCTAssertTrue((20...90).contains(memory.usedPercent), "\(scenario) memory \(memory.usedPercent)")
                XCTAssertEqual(memory.usedBytes, memory.appBytes + memory.wiredBytes + memory.compressedBytes)
                XCTAssertEqual(memory.swapUsedBytes, 0)
                XCTAssertTrue((25...80).contains(try XCTUnwrap(temperature.socMaxCelsius)), "\(scenario)")
                XCTAssertLessThan(try XCTUnwrap(temperature.socAverageCelsius), try XCTUnwrap(temperature.socMaxCelsius))
                XCTAssertEqual(temperature.sensorCount, DemoStats.sensorCount)
            }
        }
    }

    func testChargingHeadlinesRoundToTheNumbersThePanelShows() throws {
        let stats = DemoStats.current(for: .charging, at: end)
        let cpu = try XCTUnwrap(stats.cpu)
        let memory = try XCTUnwrap(stats.memory)

        XCTAssertEqual(ValueFormat.percent(cpu.totalPercent), ValueFormat.percent(24))
        XCTAssertEqual(ValueFormat.percent(cpu.userPercent), ValueFormat.percent(15))
        XCTAssertEqual(ValueFormat.percent(cpu.systemPercent), ValueFormat.percent(9))
        XCTAssertEqual(ValueFormat.percent(memory.usedPercent), ValueFormat.percent(61))
        XCTAssertEqual(stats.temperature?.socMaxCelsius, 41.2)
    }

    func testDesktopHasMoreMemoryThanTheLaptops() throws {
        let laptop = try XCTUnwrap(DemoStats.current(for: .charging, at: end).memory)
        let desktop = try XCTUnwrap(DemoStats.current(for: .desktop, at: end).memory)

        XCTAssertGreaterThan(desktop.totalBytes, laptop.totalBytes)
    }
}
