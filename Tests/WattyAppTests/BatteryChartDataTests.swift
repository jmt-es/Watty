import XCTest
@testable import Watty
import WattyCore

final class BatteryChartDataTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    private func sample(_ minutes: Double, _ level: Int, charging: Bool = false, adapter: Bool = false) -> BatteryHistorySample {
        BatteryHistorySample(date: origin.addingTimeInterval(minutes * 60), level: level, isCharging: charging, onAdapter: adapter)
    }

    func testSingleStateIsOneSegment() {
        let segments = BatteryChartSegment.segments(from: [sample(0, 80), sample(1, 79), sample(2, 78)])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].samples.count, 3)
        XCTAssertFalse(segments[0].isCharging)
    }

    func testChargingChangeSplitsWithSharedBoundarySample() {
        let segments = BatteryChartSegment.segments(from: [sample(0, 50), sample(1, 49), sample(2, 50, charging: true), sample(3, 52, charging: true), sample(4, 51)])
        XCTAssertEqual(segments.map(\.isCharging), [false, true, false])
        XCTAssertEqual(segments[0].samples.map(\.level), [50, 49])
        XCTAssertEqual(segments[1].samples.map(\.level), [49, 50, 52])
        XCTAssertEqual(segments[2].samples.map(\.level), [52, 51])
        XCTAssertEqual(Set(segments.map(\.id)).count, 3)
    }

    func testGapBreaksTheLine() {
        let segments = BatteryChartSegment.segments(from: [sample(0, 80), sample(1, 79), sample(120, 70), sample(121, 69)])
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[1].samples.first?.level, 70)
    }

    func testEmptyHistoryHasNoSegments() {
        XCTAssertTrue(BatteryChartSegment.segments(from: []).isEmpty)
    }

    func testVisibleSamplesFilterTheWindow() {
        let samples = (0..<600).map { sample(Double($0), 80 - ($0 / 10)) }
        let end = origin.addingTimeInterval(600 * 60)
        let visible = BatteryChartData.visibleSamples(samples, range: .oneHour, windowEnd: end)
        XCTAssertEqual(visible.count, 60)
        XCTAssertGreaterThanOrEqual(visible.first!.date, end.addingTimeInterval(-3_600))
    }

    func testDownsamplingCapsPointsButKeepsChargingTransitions() {
        var samples: [BatteryHistorySample] = []
        for minute in 0..<1_440 {
            let charging = (400..<600).contains(minute)
            samples.append(sample(Double(minute), 50 + (minute % 7), charging: charging))
        }
        let reduced = BatteryChartData.downsampled(samples, bucket: 24 * 3_600 / 360)
        XCTAssertLessThanOrEqual(reduced.count, 380)
        XCTAssertTrue(reduced.contains { $0.date == samples[399].date })
        XCTAssertTrue(reduced.contains { $0.date == samples[599].date })
        XCTAssertEqual(reduced.last?.date, samples.last?.date)
        let segments = BatteryChartSegment.segments(from: reduced)
        XCTAssertEqual(segments.map(\.isCharging), [false, true, false])
    }

    func testDownsamplingLeavesShortHistoriesAlone() {
        let samples = (0..<50).map { sample(Double($0), 80) }
        XCTAssertEqual(BatteryChartData.downsampled(samples, bucket: 60), samples)
    }

    func testSixHourTicksLandOnEvenHours() {
        var components = DateComponents(year: 2027, month: 1, day: 15, hour: 18, minute: 11)
        components.timeZone = calendar.timeZone
        let end = calendar.date(from: components)!
        let start = end.addingTimeInterval(-6 * 3_600)
        let ticks = BatteryChartData.tickDates(range: .sixHours, start: start, end: end, calendar: calendar)
        XCTAssertEqual(ticks.map { calendar.component(.hour, from: $0) }, [14, 16])
        XCTAssertTrue(ticks.allSatisfy { calendar.component(.minute, from: $0) == 0 })
    }

    func testTicksStayClearOfTheRightEdge() {
        var components = DateComponents(year: 2027, month: 1, day: 15, hour: 18, minute: 3)
        components.timeZone = calendar.timeZone
        let end = calendar.date(from: components)!
        let ticks = BatteryChartData.tickDates(range: .sixHours, start: end.addingTimeInterval(-6 * 3_600), end: end, calendar: calendar)
        XCTAssertFalse(ticks.contains { calendar.component(.hour, from: $0) == 18 })
    }

    func testHourRangeTicksAreQuarterHours() {
        var components = DateComponents(year: 2027, month: 1, day: 15, hour: 18, minute: 7)
        components.timeZone = calendar.timeZone
        let end = calendar.date(from: components)!
        let ticks = BatteryChartData.tickDates(range: .oneHour, start: end.addingTimeInterval(-3_600), end: end, calendar: calendar)
        XCTAssertEqual(ticks.map { calendar.component(.minute, from: $0) }, [15, 30, 45, 0])
    }

    func testDayRangeTicksAreSixHours() {
        var components = DateComponents(year: 2027, month: 1, day: 15, hour: 20, minute: 41)
        components.timeZone = calendar.timeZone
        let end = calendar.date(from: components)!
        let ticks = BatteryChartData.tickDates(range: .twentyFourHours, start: end.addingTimeInterval(-24 * 3_600), end: end, calendar: calendar)
        XCTAssertEqual(ticks.map { calendar.component(.hour, from: $0) }, [0, 6, 12, 18])
    }

    func testWindowEndRoundsUpToTheNextMinute() {
        let date = origin.addingTimeInterval(37)
        let end = BatteryChartData.windowEnd(for: date, calendar: calendar)
        XCTAssertGreaterThan(end, date)
        XCTAssertLessThanOrEqual(end.timeIntervalSince(date), 60)
        XCTAssertEqual(calendar.component(.second, from: end), 0)
    }
}
