import XCTest
@testable import WattyCore

final class PluggedInDrainPeriodsTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ seconds: TimeInterval, _ level: Int, adapter: Bool = true, charging: Bool = true) -> BatteryHistorySample {
        BatteryHistorySample(date: origin.addingTimeInterval(seconds), level: level, isCharging: charging, onAdapter: adapter)
    }

    private func everyMinute(_ levels: [Int], from start: TimeInterval = 0, adapter: Bool = true, charging: Bool = true) -> [BatteryHistorySample] {
        levels.enumerated().map { sample(start + Double($0.offset) * 60, $0.element, adapter: adapter, charging: charging) }
    }

    private func seconds(_ period: DateInterval, from reference: Date) -> (start: TimeInterval, end: TimeInterval) {
        (period.start.timeIntervalSince(reference), period.end.timeIntervalSince(reference))
    }

    func testTheRealIncidentFallIsAPeriodFromTheStartToTheLowPoint() throws {
        let samples = IncidentHistoryFixture.samples()

        let periods = PluggedInDrainPeriods.detect(in: samples)

        let first = try XCTUnwrap(periods.first)
        let bounds = seconds(first, from: IncidentHistoryFixture.origin)
        XCTAssertLessThanOrEqual(bounds.start, 120)
        XCTAssertGreaterThanOrEqual(bounds.end, 1_100)
        XCTAssertLessThanOrEqual(bounds.end, 1_600)
    }

    func testTheFlatStretchAfterTheRealIncidentIsNotADrain() {
        let flatStart = IncidentHistoryFixture.origin.addingTimeInterval(1_500)
        let flatEnd = IncidentHistoryFixture.origin.addingTimeInterval(3_800)

        let periods = PluggedInDrainPeriods.detect(in: IncidentHistoryFixture.samples())

        XCTAssertFalse(periods.contains { $0.intersects(DateInterval(start: flatStart, end: flatEnd)) }, "\(periods)")
    }

    func testTheRealIncidentIsADrainEvenWhileMacOSSaysNotCharging() {
        let periods = PluggedInDrainPeriods.detect(in: IncidentHistoryFixture.samples(charging: false))

        XCTAssertFalse(periods.isEmpty)
    }

    func testTheSameFallOnBatteryIsNotAPluggedInDrain() {
        XCTAssertTrue(PluggedInDrainPeriods.detect(in: IncidentHistoryFixture.samples(charging: false, adapter: false)).isEmpty)
    }

    func testAFlatLevelHasNoPeriods() {
        XCTAssertTrue(PluggedInDrainPeriods.detect(in: everyMinute(Array(repeating: 80, count: 30))).isEmpty)
    }

    func testTwoPointsOfJitterAroundAFlatLevelHaveNoPeriods() {
        let jitter = [13, 12, 14, 13, 12, 13, 14, 12, 13, 14, 13, 12, 14, 13, 12, 13, 14, 13]

        XCTAssertTrue(PluggedInDrainPeriods.detect(in: everyMinute(jitter)).isEmpty)
    }

    func testARisingLevelHasNoPeriods() {
        XCTAssertTrue(PluggedInDrainPeriods.detect(in: everyMinute(Array(20...60))).isEmpty)
    }

    func testAFallOfTwoPointsIsIgnored() {
        XCTAssertTrue(PluggedInDrainPeriods.detect(in: everyMinute([50, 50, 50, 49, 49, 49, 48, 48, 48, 48])).isEmpty)
    }

    func testASteadyFallIsOnePeriodFromThePeakToTheLowPoint() throws {
        let levels = Array(repeating: 60, count: 4) + Array(stride(from: 59, through: 40, by: -1)) + Array(repeating: 40, count: 6)

        let periods = PluggedInDrainPeriods.detect(in: everyMinute(levels))

        XCTAssertEqual(periods.count, 1)
        let bounds = seconds(try XCTUnwrap(periods.first), from: origin)
        XCTAssertEqual(bounds.start, 3 * 60, accuracy: 120)
        XCTAssertEqual(bounds.end, 23 * 60, accuracy: 120)
    }

    func testTwoFallsSeparatedByARiseAreTwoPeriods() {
        let levels = Array(stride(from: 80, through: 60, by: -1)) + Array(stride(from: 61, through: 75, by: 1)) + Array(stride(from: 74, through: 50, by: -1))

        XCTAssertEqual(PluggedInDrainPeriods.detect(in: everyMinute(levels)).count, 2)
    }

    func testAGapSplitsTheRunSoTheFallsDoNotJoinAcrossIt() {
        let first = everyMinute(Array(stride(from: 80, through: 70, by: -1)))
        let second = everyMinute(Array(stride(from: 70, through: 60, by: -1)), from: 60 * 60)

        let periods = PluggedInDrainPeriods.detect(in: first + second)

        XCTAssertEqual(periods.count, 2)
    }

    func testUnpluggedSamplesBetweenTwoFallsSplitThem() {
        let plugged = everyMinute(Array(stride(from: 80, through: 70, by: -1)))
        let unplugged = everyMinute(Array(stride(from: 70, through: 60, by: -1)), from: 11 * 60, adapter: false, charging: false)
        let pluggedAgain = everyMinute(Array(stride(from: 60, through: 50, by: -1)), from: 22 * 60)

        let periods = PluggedInDrainPeriods.detect(in: plugged + unplugged + pluggedAgain)

        XCTAssertEqual(periods.count, 2)
        XCTAssertTrue(periods.allSatisfy { $0.end <= origin.addingTimeInterval(11 * 60) || $0.start >= origin.addingTimeInterval(22 * 60) })
    }

    func testAnOngoingFallEndsAtItsLatestLowPoint() throws {
        let levels = [60, 60, 59, 58, 57, 56, 55, 54, 53]

        let periods = PluggedInDrainPeriods.detect(in: everyMinute(levels))

        let bounds = seconds(try XCTUnwrap(periods.first), from: origin)
        XCTAssertEqual(bounds.end, 8 * 60, accuracy: 90)
    }

    func testSamplesInAnyOrderGiveTheSamePeriods() {
        let samples = IncidentHistoryFixture.samples()

        XCTAssertEqual(PluggedInDrainPeriods.detect(in: samples.reversed()), PluggedInDrainPeriods.detect(in: samples))
        XCTAssertEqual(PluggedInDrainPeriods.detect(in: samples.shuffledDeterministically()), PluggedInDrainPeriods.detect(in: samples))
    }

    func testTooFewSamplesHaveNoPeriods() {
        XCTAssertTrue(PluggedInDrainPeriods.detect(in: []).isEmpty)
        XCTAssertTrue(PluggedInDrainPeriods.detect(in: [sample(0, 50)]).isEmpty)
    }
}

private extension Array {
    func shuffledDeterministically() -> [Element] {
        enumerated().sorted { ($0.offset * 7919) % 1009 < ($1.offset * 7919) % 1009 }.map(\.element)
    }
}
