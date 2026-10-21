import XCTest
@testable import WattyCore

final class PowerReadingSanitizerTests: XCTestCase {
    func testPositiveReadingWhileUnpluggedBecomesADischarge() {
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(21.9, onExternalPower: false), -21.9)
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(0.4, onExternalPower: false), -0.4)
    }

    func testNegativeReadingWhileUnpluggedIsUnchanged() {
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(-8.4, onExternalPower: false), -8.4)
    }

    func testReadingsKeepTheirSignOnExternalPower() {
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(19.8, onExternalPower: true), 19.8)
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(-3.2, onExternalPower: true), -3.2)
    }

    func testZeroNeverBecomesNegativeZero() {
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(0, onExternalPower: false)?.sign, .plus)
        XCTAssertEqual(PowerReadingSanitizer.batteryFlow(0, onExternalPower: true)?.sign, .plus)
    }

    func testMissingBatteryReadingStaysMissing() {
        XCTAssertNil(PowerReadingSanitizer.batteryFlow(nil, onExternalPower: false))
        XCTAssertNil(PowerReadingSanitizer.batteryFlow(nil, onExternalPower: true))
    }

    func testNegativeSystemLoadIsInvalid() {
        XCTAssertNil(PowerReadingSanitizer.systemLoad(-21.9))
        XCTAssertNil(PowerReadingSanitizer.systemLoad(-0.001))
        XCTAssertNil(PowerReadingSanitizer.systemLoad(.nan))
    }

    func testNonNegativeSystemLoadIsKept() {
        XCTAssertEqual(PowerReadingSanitizer.systemLoad(21.3), 21.3)
        XCTAssertEqual(PowerReadingSanitizer.systemLoad(0), 0)
        XCTAssertNil(PowerReadingSanitizer.systemLoad(nil))
    }
}
