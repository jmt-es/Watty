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
        for (level, charging) in [(0, false), (76, true), (100, false)] {
            let ring = BatteryLevelRing(level: level, tint: .green, isCharging: charging)
            let size = NSHostingView(rootView: ring).fittingSize

            XCTAssertEqual(size.width, BatteryLevelRing.diameter, "width at \(level)%")
            XCTAssertEqual(size.height, BatteryLevelRing.diameter, "height at \(level)%")
        }
    }
}
