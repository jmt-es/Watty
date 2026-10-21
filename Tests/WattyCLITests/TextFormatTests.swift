import XCTest
@testable import WattyCLI

final class TextFormatTests: XCTestCase {
    func testUnknownValuesPrintAsDash() {
        XCTAssertEqual(TextFormat.missing, "—")
        XCTAssertEqual(TextFormat.watts(nil), "—")
        XCTAssertEqual(TextFormat.signedWatts(nil), "—")
        XCTAssertEqual(TextFormat.volts(nil), "—")
        XCTAssertEqual(TextFormat.signedAmps(nil), "—")
        XCTAssertEqual(TextFormat.celsius(nil), "—")
        XCTAssertEqual(TextFormat.percent(nil as Double?), "—")
        XCTAssertEqual(TextFormat.percent(nil as Int?), "—")
        XCTAssertEqual(TextFormat.integer(nil), "—")
        XCTAssertEqual(TextFormat.bytes(nil), "—")
    }

    func testPowerValuesUseOneDecimalAndExplicitSigns() {
        XCTAssertEqual(TextFormat.watts(30.468), "30.5 W")
        XCTAssertEqual(TextFormat.signedWatts(29.34), "+29.3 W")
        XCTAssertEqual(TextFormat.signedWatts(-11.24), "-11.2 W")
        XCTAssertEqual(TextFormat.signedWatts(0.01), "0.0 W")
        XCTAssertEqual(TextFormat.signedWatts(-0.04), "0.0 W")
        XCTAssertEqual(TextFormat.signedNumber(-0.04), "0.0")
        XCTAssertEqual(TextFormat.number(7), "7.0")
    }

    func testElectricalAndThermalValues() {
        XCTAssertEqual(TextFormat.volts(12.323), "12.32 V")
        XCTAssertEqual(TextFormat.signedAmps(2.381), "+2.38 A")
        XCTAssertEqual(TextFormat.signedAmps(-0.91), "-0.91 A")
        XCTAssertEqual(TextFormat.signedAmps(0.001), "0.00 A")
        XCTAssertEqual(TextFormat.celsius(30.6), "30.6 °C")
    }

    func testPercentages() {
        XCTAssertEqual(TextFormat.percent(12.4), "12.4%")
        XCTAssertEqual(TextFormat.percent(100.0), "100.0%")
        XCTAssertEqual(TextFormat.percent(72 as Int?), "72%")
    }

    func testBytesUseBinaryUnitsWithThreeSignificantDigits() {
        XCTAssertEqual(TextFormat.bytes(512), "512 B")
        XCTAssertEqual(TextFormat.bytes(1536), "1.50 KB")
        XCTAssertEqual(TextFormat.bytes(4_014_368), "3.83 MB")
        XCTAssertEqual(TextFormat.bytes(387_927_040), "370 MB")
        XCTAssertEqual(TextFormat.bytes(2_000_000_000), "1.86 GB")
        XCTAssertEqual(TextFormat.bytes(17_179_869_184), "16.0 GB")
        XCTAssertEqual(TextFormat.bytes(34_359_738_368), "32.0 GB")
        XCTAssertEqual(TextFormat.bytes(3 * 1_099_511_627_776), "3.00 TB")
        XCTAssertEqual(TextFormat.bytes(0), "0 B")
    }

    func testBatteryFlowLabelsFollowTheAppThreshold() {
        XCTAssertEqual(TextFormat.batteryFlow(12), "charging")
        XCTAssertEqual(TextFormat.batteryFlow(-12), "discharging")
        XCTAssertEqual(TextFormat.batteryFlow(0.3), "idle")
        XCTAssertEqual(TextFormat.batteryFlow(-0.3), "idle")
        XCTAssertNil(TextFormat.batteryFlow(nil))
    }

    func testSecondsDropTrailingZeros() {
        XCTAssertEqual(TextFormat.seconds(1), "1 s")
        XCTAssertEqual(TextFormat.seconds(0.5), "0.5 s")
        XCTAssertEqual(TextFormat.seconds(2.25), "2.25 s")
    }

    func testClockMatchesTheAppFormat() {
        XCTAssertEqual(TextFormat.clock(minutes: 98), "1:38")
        XCTAssertEqual(TextFormat.clock(minutes: 5), "0:05")
    }
}
