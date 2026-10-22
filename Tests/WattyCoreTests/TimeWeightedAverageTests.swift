import XCTest
@testable import WattyCore

final class TimeWeightedAverageTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(_ seconds: TimeInterval, _ value: Double) -> TimedValue {
        TimedValue(date: origin.addingTimeInterval(seconds), value: value)
    }

    private func mean(_ points: [TimedValue], from start: TimeInterval, to end: TimeInterval) -> TimeWeightedMean? {
        TimeWeightedAverage.mean(of: points, from: origin.addingTimeInterval(start), to: origin.addingTimeInterval(end))
    }

    func testNoPointsHaveNoAverage() {
        XCTAssertNil(mean([], from: 0, to: 60))
    }

    func testASinglePointIsItsOwnAverageWithoutCoverage() throws {
        let result = try XCTUnwrap(mean([point(10, -12)], from: 0, to: 60))

        XCTAssertEqual(result.value, -12)
        XCTAssertEqual(result.coveredSeconds, 0)
    }

    func testEvenlySpacedPointsAverageLikeTheirMean() throws {
        let points = [point(0, -10), point(2, -20), point(4, -30)]

        let result = try XCTUnwrap(mean(points, from: 0, to: 4))

        XCTAssertEqual(result.value, -20, accuracy: 0.0001)
        XCTAssertEqual(result.coveredSeconds, 4)
    }

    func testALongIntervalWeighsMoreThanAShortOne() throws {
        let points = [point(0, 0), point(1, 0), point(1.5, -30), point(31.5, -30)]

        let result = try XCTUnwrap(mean(points, from: 0, to: 31.5))

        let expected = (0.0 * 1 + (0 + -30) / 2 * 0.5 + -30 * 30) / 31.5
        XCTAssertEqual(result.value, expected, accuracy: 0.0001)
    }

    func testThePointsAreInterpolatedWhereTheWindowStartsInsideAnInterval() throws {
        let points = [point(0, 0), point(100, -100)]

        let result = try XCTUnwrap(mean(points, from: 50, to: 100))

        XCTAssertEqual(result.value, -75, accuracy: 0.0001)
        XCTAssertEqual(result.coveredSeconds, 50)
    }

    func testPointsAfterTheWindowAreIgnored() throws {
        let points = [point(0, 10), point(60, 10), point(120, -500)]

        let result = try XCTUnwrap(mean(points, from: 0, to: 60))

        XCTAssertEqual(result.value, 10, accuracy: 0.0001)
    }

    func testAPositiveSpikeBarelyMovesAnAverageOverASteadyDrain() throws {
        var points = (0...60).map { point(Double($0) * 2, -20) }
        points[30] = point(60, 4.8)

        let result = try XCTUnwrap(mean(points, from: 0, to: 120))

        XCTAssertLessThan(result.value, -19)
    }
}
