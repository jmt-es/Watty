import XCTest
@testable import WattyCore

final class PowerAccumulationParsingTests: XCTestCase {
    private static let negativeDischargeAsUnsigned: UInt64 = 18_446_744_071_188_733_378

    private func telemetry(overrides: [String: Any] = [:]) -> [String: Any] {
        var properties: [String: Any] = [
            "Voltage": 11_228,
            "InstantAmperage": 2_000,
            "PowerTelemetryData": [
                "BatteryPower": 1_506,
                "AccumulatedBatteryPower": 2_653_160_571,
                "BatteryPowerAccumulatorCount": 126_349,
                "AccumulatedBatteryDischarge": Self.negativeDischargeAsUnsigned,
                "BatteryDischargeAccumulatorCount": 166_218
            ] as [String: Any]
        ]
        for (key, value) in overrides { properties[key] = value }
        return properties
    }

    func testTheChargeAndDischargeAccumulatorsBecomeOneNetAccumulation() throws {
        let info = TelemetryParsers.parseSmartBatteryProperties(telemetry())

        let accumulation = try XCTUnwrap(info.powerAccumulation)
        XCTAssertEqual(accumulation.milliwattTicks, 2_653_160_571 - 2_520_818_238)
        XCTAssertEqual(accumulation.ticks, 126_349 + 166_218)
    }

    func testTheTextFallbackReadsTheSameAccumulation() throws {
        let text = #"""
        "Voltage" = 11228
        "InstantAmperage" = 2000
        "PowerTelemetryData" = {"SystemPowerIn"=43529,"SystemLoad"=42023,"AccumulatedBatteryPower"=2653160571,"BatteryPowerAccumulatorCount"=126349,"AccumulatedBatteryDischarge"=18446744071188733378,"BatteryDischargeAccumulatorCount"=166218,"BatteryPower"=1506}
        """#

        let fromText = TelemetryParsers.parseIoregBattery(text)

        XCTAssertEqual(fromText.powerAccumulation, TelemetryParsers.parseSmartBatteryProperties(telemetry()).powerAccumulation)
        XCTAssertEqual(fromText.powerAccumulation, PowerAccumulation(milliwattTicks: 132_342_333, ticks: 292_567))
    }

    func testWithoutEveryAccumulatorThereIsNoAccumulation() {
        let partial: [String: Any] = [
            "PowerTelemetryData": [
                "AccumulatedBatteryPower": 2_653_160_571,
                "BatteryPowerAccumulatorCount": 126_349,
                "AccumulatedBatteryDischarge": Self.negativeDischargeAsUnsigned
            ] as [String: Any]
        ]

        XCTAssertNil(TelemetryParsers.parseSmartBatteryProperties(partial).powerAccumulation)
        XCTAssertNil(TelemetryParsers.parseSmartBatteryProperties(["Voltage": 12_000]).powerAccumulation)
        XCTAssertNil(TelemetryParsers.parseIoregBattery(#""Voltage" = 12000"#).powerAccumulation)
    }

    func testAnOverflowingAccumulationIsDiscarded() {
        let overflowing: [String: Any] = [
            "PowerTelemetryData": [
                "AccumulatedBatteryPower": Int64.max,
                "BatteryPowerAccumulatorCount": 1,
                "AccumulatedBatteryDischarge": Int64(1),
                "BatteryDischargeAccumulatorCount": 1
            ] as [String: Any]
        ]

        XCTAssertNil(TelemetryParsers.parseSmartBatteryProperties(overflowing).powerAccumulation)
    }

    func testTheAccumulatorsDoNotChangeTheInstantaneousBatteryPower() throws {
        let info = TelemetryParsers.parseSmartBatteryProperties(telemetry())

        XCTAssertEqual(try XCTUnwrap(info.batteryPowerWatts), 11.228 * 2.0, accuracy: 0.0001)
    }
}
