import XCTest
@testable import WattyCore

final class LevelSwingsTests: XCTestCase {
    private func pivots(_ levels: [Double], swing: Double = 3) -> [LevelPivot] {
        LevelSwings.pivots(in: levels, minimumSwing: swing)
    }

    func testNothingMovesInAFlatSeries() {
        XCTAssertEqual(pivots([5, 5, 5, 5]), [])
    }

    func testASeriesShorterThanTwoPointsHasNoPivots() {
        XCTAssertEqual(pivots([]), [])
        XCTAssertEqual(pivots([5]), [])
    }

    func testAFallBecomesAPeakAndATrough() {
        XCTAssertEqual(pivots([10, 10, 9, 8, 7, 6]), [LevelPivot(index: 1, isPeak: true), LevelPivot(index: 5, isPeak: false)])
    }

    func testARiseBecomesATroughAndAPeak() {
        XCTAssertEqual(pivots([6, 7, 8, 9, 10]), [LevelPivot(index: 0, isPeak: false), LevelPivot(index: 4, isPeak: true)])
    }

    func testMovesSmallerThanTheSwingAreIgnored() {
        XCTAssertEqual(pivots([10, 9, 10, 8, 9, 10]), [])
    }

    func testAReversalOfTheSwingStartsANewLeg() {
        let result = pivots([10, 7, 7, 10, 13, 9])

        XCTAssertEqual(result, [
            LevelPivot(index: 0, isPeak: true),
            LevelPivot(index: 1, isPeak: false),
            LevelPivot(index: 4, isPeak: true),
            LevelPivot(index: 5, isPeak: false)
        ])
    }

    func testAPlateauAtTheBottomEndsTheFallAtItsFirstPoint() {
        let result = pivots([10, 8, 6, 6, 6, 6])

        XCTAssertEqual(result.last, LevelPivot(index: 2, isPeak: false))
    }

    func testAPlateauAtTheTopStartsTheFallAtItsLastPoint() {
        let result = pivots([10, 10, 10, 9, 8, 7])

        XCTAssertEqual(result.first, LevelPivot(index: 2, isPeak: true))
    }
}
