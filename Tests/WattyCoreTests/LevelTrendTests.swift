import XCTest
@testable import WattyCore

final class LevelTrendTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func series(_ levels: [(seconds: TimeInterval, level: Int)]) -> LevelSeries {
        var series = LevelSeries()
        for entry in levels {
            series.append(LevelPoint(date: origin.addingTimeInterval(entry.seconds), level: entry.level))
        }
        return series
    }

    private func evenlySpaced(_ levels: [Int], every spacing: TimeInterval = 30) -> LevelSeries {
        series(levels.enumerated().map { (seconds: Double($0.offset) * spacing, level: $0.element) })
    }

    func testTooFewPointsHaveNoTrend() {
        XCTAssertNil(LevelTrend.estimate(from: evenlySpaced([50, 49, 48, 47])))
    }

    func testAShortSpanHasNoTrend() {
        XCTAssertNil(LevelTrend.estimate(from: evenlySpaced([50, 49, 48, 47, 46, 45], every: 10)))
    }

    func testASteadyFallIsFalling() throws {
        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced([40, 39, 39, 38, 37, 37, 36, 35, 34, 34, 33, 32, 31])))

        XCTAssertEqual(trend.direction, .falling)
        XCTAssertLessThan(trend.pointsPerMinute, -0.3)
    }

    func testASteadyRiseIsRising() throws {
        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced([20, 21, 22, 22, 23, 24, 25, 25, 26, 27, 28, 28, 29])))

        XCTAssertEqual(trend.direction, .rising)
    }

    func testAFlatLevelIsSteady() throws {
        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced([50, 50, 50, 50, 50, 50, 50, 50, 50, 50])))

        XCTAssertEqual(trend.direction, .steady)
        XCTAssertEqual(trend.pointsPerMinute, 0, accuracy: 0.0001)
    }

    func testTwoPointsOfJitterAroundAFlatLevelAreSteady() throws {
        let jittery = [13, 12, 13, 14, 12, 13, 14, 13, 12, 14, 13, 12, 13, 14, 12, 13]

        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced(jittery)))

        XCTAssertEqual(trend.direction, .steady)
    }

    func testTwoPointsOfJitterDoNotHideAFall() throws {
        let falling = [27, 26, 27, 25, 24, 25, 23, 22, 23, 21, 20, 21, 19, 18, 19, 17, 16]

        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced(falling)))

        XCTAssertEqual(trend.direction, .falling)
    }

    func testASingleOutlierDoesNotMakeAFlatLevelFall() throws {
        let levels = [40, 40, 40, 40, 40, 40, 31, 40, 40, 40, 40, 40]

        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced(levels)))

        XCTAssertEqual(trend.direction, .steady)
    }

    func testFallingPointsNeedARealChangeNotJustASlopeOfOnePoint() throws {
        let levels = [40, 40, 39, 39, 39, 39, 39, 39, 39, 39]

        let trend = try XCTUnwrap(LevelTrend.estimate(from: evenlySpaced(levels)))

        XCTAssertEqual(trend.direction, .steady)
    }

    func testPointsInTheSameBucketKeepOnlyTheLatest() {
        var series = LevelSeries()
        series.append(LevelPoint(date: origin, level: 50))
        series.append(LevelPoint(date: origin.addingTimeInterval(4), level: 49))
        series.append(LevelPoint(date: origin.addingTimeInterval(20), level: 48))

        XCTAssertEqual(series.points.map(\.level), [49, 48])
    }

    func testPointsOlderThanTheWindowAreDropped() {
        var series = LevelSeries()
        series.append(LevelPoint(date: origin, level: 50))
        series.append(LevelPoint(date: origin.addingTimeInterval(NetFlowRules.Trend.window + 1), level: 49))

        XCTAssertEqual(series.points.map(\.level), [49])
    }
}
