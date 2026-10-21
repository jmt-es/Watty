import XCTest
@testable import Watty

final class FormattingTests: XCTestCase {
    func testMissingValuesUseAPlaceholder() {
        XCTAssertEqual(ValueFormat.watts(nil), ValueFormat.missing)
        XCTAssertEqual(ValueFormat.signedWatts(nil), ValueFormat.missing)
        XCTAssertEqual(ValueFormat.celsius(nil), ValueFormat.missing)
        XCTAssertEqual(ValueFormat.percent(nil as Int?), ValueFormat.missing)
        XCTAssertEqual(ValueFormat.integer(nil), ValueFormat.missing)
    }

    func testSignedWattsTreatsTinyValuesAsZero() {
        XCTAssertEqual(ValueFormat.signedWatts(0.04), ValueFormat.watts(0))
        XCTAssertEqual(ValueFormat.signedWatts(-0.04), ValueFormat.watts(0))
        XCTAssertTrue(ValueFormat.signedWatts(5).contains("+"))
        XCTAssertTrue(ValueFormat.signedWatts(-5).contains("-"))
    }

    func testPercentUsesTheLocalePercentStyle() {
        XCTAssertEqual(ValueFormat.percent(82), (0.82).formatted(.percent.precision(.fractionLength(0))))
        XCTAssertEqual(ValueFormat.percent(81.6), (0.82).formatted(.percent.precision(.fractionLength(0))))
    }

    func testCPUPercentKeepsADecimalOnlyBelowTen() {
        XCTAssertEqual(ValueFormat.cpuPercent(5.25), (0.0525).formatted(.percent.precision(.fractionLength(1))))
        XCTAssertEqual(ValueFormat.cpuPercent(42.4), (0.42).formatted(.percent.precision(.fractionLength(0))))
    }

    func testRelativeTimeBuckets() {
        let now = Date()
        XCTAssertEqual(ValueFormat.relative(now, now: now), String(localized: "just now"))
        XCTAssertEqual(ValueFormat.relative(now.addingTimeInterval(-30), now: now), String(localized: "\(30) s ago"))
        XCTAssertEqual(ValueFormat.relative(now.addingTimeInterval(-300), now: now), String(localized: "\(5) min ago"))
        XCTAssertEqual(ValueFormat.relative(now.addingTimeInterval(-3_900), now: now), String(localized: "\(1) h \(5) min ago"))
        XCTAssertEqual(ValueFormat.relative(now.addingTimeInterval(10), now: now), String(localized: "just now"))
    }
}
