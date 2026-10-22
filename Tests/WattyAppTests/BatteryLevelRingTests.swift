import AppKit
import SwiftUI
import XCTest
@testable import Watty

@MainActor
final class BatteryLevelRingTests: XCTestCase {
    func testFractionIsTheLevelAsAShareOfTheRing() {
        XCTAssertEqual(BatteryLevelRing.fraction(forLevel: 0), 0)
        XCTAssertEqual(BatteryLevelRing.fraction(forLevel: 76), 0.76, accuracy: 0.0001)
        XCTAssertEqual(BatteryLevelRing.fraction(forLevel: 100), 1)
    }

    func testFractionIsClampedToTheRing() {
        XCTAssertEqual(BatteryLevelRing.fraction(forLevel: -4), 0)
        XCTAssertEqual(BatteryLevelRing.fraction(forLevel: 120), 1)
    }

    func testRingKeepsItsFixedSizeWhateverTheLevelOrState() {
        let states: [(level: Int, symbol: String?)] = [
            (0, nil), (76, ChargeSymbol.charging), (18, ChargeSymbol.draining), (100, nil)
        ]
        for state in states {
            let ring = BatteryLevelRing(level: state.level, tint: .green, symbol: state.symbol)
            let size = NSHostingView(rootView: ring).fittingSize

            XCTAssertEqual(size.width, BatteryLevelRing.diameter, "width at \(state.level)%")
            XCTAssertEqual(size.height, BatteryLevelRing.diameter, "height at \(state.level)%")
        }
    }
}
