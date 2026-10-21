import XCTest
@testable import Watty
import WattyCore

final class DemoBatteryHistoryTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_800_000_000.4)

    private func samples(_ scenario: DemoScenario) -> [BatteryHistorySample] {
        DemoBatteryHistory.samples(for: scenario, endingAt: end)
    }

    func testChargingHistoryCoversAlmostAFullDayMinuteByMinute() throws {
        let samples = samples(.charging)

        XCTAssertEqual(samples.count, DemoBatteryHistory.coveredMinutes + 1)
        XCTAssertEqual(
            try XCTUnwrap(samples.last).date.timeIntervalSince(try XCTUnwrap(samples.first).date),
            Double(DemoBatteryHistory.coveredMinutes) * 60
        )
        for (previous, next) in zip(samples, samples.dropFirst()) {
            XCTAssertEqual(next.date.timeIntervalSince(previous.date), 60)
        }
    }

    func testChargingHistoryEndsOnTheChargingSnapshot() throws {
        let latest = try XCTUnwrap(samples(.charging).last)

        XCTAssertEqual(latest.level, DemoSnapshot.chargingLevel)
        XCTAssertTrue(latest.isCharging)
        XCTAssertTrue(latest.onAdapter)
    }

    func testBatteryHistoryEndsOnTheDischargingSnapshot() throws {
        let latest = try XCTUnwrap(samples(.battery).last)

        XCTAssertEqual(latest.level, DemoSnapshot.onBatteryLevel)
        XCTAssertFalse(latest.isCharging)
        XCTAssertFalse(latest.onAdapter)
    }

    func testChargingHistoryHasADayOfDischargeAndSeveralChargingPeriods() {
        let samples = samples(.charging)
        let segments = BatteryChartSegment.segments(from: samples)

        XCTAssertTrue(segments.contains { $0.isCharging })
        XCTAssertTrue(segments.contains { !$0.isCharging })
        XCTAssertTrue(samples.contains { $0.onAdapter && !$0.isCharging && $0.level == 100 })
        XCTAssertGreaterThan(samples.filter { !$0.onAdapter }.count, 600)
        XCTAssertLessThanOrEqual(samples.map(\.level).min() ?? 0, 30)
    }

    func testTheSixHourWindowShowsTheDischargeAndTheCharge() {
        let windowEnd = BatteryChartData.windowEnd(for: end)
        let visible = BatteryChartData.visibleSamples(samples(.charging), range: .sixHours, windowEnd: windowEnd)
        let segments = BatteryChartSegment.segments(from: visible)

        XCTAssertEqual(segments.map(\.isCharging), [false, true])
        XCTAssertGreaterThan(visible.first?.level ?? 0, 50)
    }

    func testDischargeNeverClimbsAndChargeNeverFalls() {
        let samples = samples(.charging)

        for (previous, next) in zip(samples, samples.dropFirst()) {
            if !next.onAdapter { XCTAssertLessThanOrEqual(next.level, previous.level) }
            if next.isCharging, previous.isCharging { XCTAssertGreaterThanOrEqual(next.level, previous.level) }
        }
    }

    func testLevelsStayWithinTheBatteryRange() {
        for scenario in DemoScenario.allCases {
            XCTAssertTrue(samples(scenario).allSatisfy { (0...100).contains($0.level) }, "\(scenario)")
        }
    }

    func testDesktopHasNoBatteryHistory() {
        XCTAssertTrue(samples(.desktop).isEmpty)
    }

    func testHistoryIsDeterministic() {
        for scenario in DemoScenario.allCases {
            XCTAssertEqual(samples(scenario), samples(scenario))
        }
    }

    func testTheStoreKeepsEverySampleInMemoryAndNeverTouchesTheDisk() {
        let store = DemoBatteryHistory.makeStore(for: .charging, endingAt: end)

        XCTAssertEqual(store.history.samples, samples(.charging))

        store.save()
        store.saveIfDue(now: end.addingTimeInterval(BatteryHistoryStore.saveInterval * 2))

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.deletingLastPathComponent().path))
        XCTAssertFalse(store.isSaveFailing)
    }

    func testTheStoreNeverReadsTheUsersHistory() {
        let userHistory = BatteryHistoryStore.defaultFileURL

        let store = DemoBatteryHistory.makeStore(for: .charging, endingAt: end)
        store.load()

        XCTAssertNotEqual(store.fileURL, userHistory)
        XCTAssertEqual(store.history.samples, samples(.charging))
    }
}
