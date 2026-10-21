import XCTest
@testable import Watty

final class DemoSignalTests: XCTestCase {
    private let waves = [2.7, 5.3, 11.1]

    func testDeviationIsZeroNow() {
        let signal = DemoSignal(seed: 3, cyclesPerWindow: waves)

        XCTAssertEqual(signal.deviation(secondsAgo: 0), 0)
    }

    func testTheSameSeedGivesTheSameCurve() {
        let first = DemoSignal(seed: 3, cyclesPerWindow: waves)
        let repeated = DemoSignal(seed: 3, cyclesPerWindow: waves)
        let other = DemoSignal(seed: 4, cyclesPerWindow: waves)

        XCTAssertEqual(first.deviation(secondsAgo: 120), repeated.deviation(secondsAgo: 120))
        XCTAssertNotEqual(first.deviation(secondsAgo: 120), other.deviation(secondsAgo: 120))
    }

    func testCurveMovesButStaysBounded() {
        let signal = DemoSignal(seed: 3, cyclesPerWindow: waves)
        let deviations = stride(from: 0.0, through: 600, by: 2).map { signal.deviation(secondsAgo: $0) }

        XCTAssertGreaterThan((deviations.max() ?? 0) - (deviations.min() ?? 0), 0.3)
        XCTAssertTrue(deviations.allSatisfy { abs($0) <= 2 })
    }
}
