import XCTest
@testable import WattyCore

final class PowerSourceReaderTests: XCTestCase {
    func testParsesChargingInternalBattery() {
        let description: [String: Any] = [
            "Type": "InternalBattery",
            "Current Capacity": 86,
            "Max Capacity": 100,
            "Is Charging": 1,
            "Is Finishing Charge": 1,
            "Power Source State": "AC Power",
            "Time to Full Charge": 43,
            "Time to Empty": 0,
            "LPM Active": 0
        ]

        let info = PowerSourceReader.parse(description: description, providingType: "AC Power")

        XCTAssertEqual(info.level, 86)
        XCTAssertEqual(info.isCharging, true)
        XCTAssertNil(info.isCharged)
        XCTAssertEqual(info.isFinishingCharge, true)
        XCTAssertEqual(info.externalPower, true)
        XCTAssertEqual(info.timeToFullMinutes, 43)
        XCTAssertNil(info.timeToEmptyMinutes)
        XCTAssertEqual(info.lowPowerModeActive, false)
    }

    func testParsesDischargingBatteryWithUnknownEstimate() {
        let description: [String: Any] = [
            "Current Capacity": 40,
            "Max Capacity": 100,
            "Is Charging": 0,
            "Power Source State": "Battery Power",
            "Time to Empty": -1,
            "LPM Active": 1
        ]

        let info = PowerSourceReader.parse(description: description, providingType: nil)

        XCTAssertEqual(info.level, 40)
        XCTAssertEqual(info.isCharging, false)
        XCTAssertEqual(info.externalPower, false)
        XCTAssertNil(info.timeToEmptyMinutes)
        XCTAssertEqual(info.lowPowerModeActive, true)
    }

    func testSelectsTheInternalBatteryAmongSeveralPowerSources() {
        let upsAndBattery: [[String: Any]] = [
            ["Type": "UPS", "Current Capacity": 10, "Max Capacity": 100],
            ["Type": "InternalBattery", "Current Capacity": 55, "Max Capacity": 100, "Power Source State": "Battery Power"]
        ]

        let result = PowerSourceReader.select(descriptions: upsAndBattery, providingType: "Battery Power")

        XCTAssertEqual(result.internalBattery?.level, 55)
        XCTAssertEqual(result.internalBattery?.externalPower, false)
    }

    func testReportsNoInternalBatteryForDesktopsAndUPSOnlySetups() {
        XCTAssertEqual(PowerSourceReader.select(descriptions: [], providingType: "AC Power"), .noInternalBattery)
        XCTAssertEqual(
            PowerSourceReader.select(descriptions: [["Type": "UPS", "Current Capacity": 90, "Max Capacity": 100]], providingType: "AC Power"),
            .noInternalBattery
        )
    }

    func testReadResultAgreesWithLegacyRead() {
        XCTAssertEqual(PowerSourceReader.readResult().internalBattery?.level != nil, PowerSourceReader.read() != nil)
    }

    func testReadsLiveInternalBattery() throws {
        try XCTSkipIf(PowerSourceReader.readResult().internalBattery == nil, "No internal battery on this machine")

        let info = try XCTUnwrap(PowerSourceReader.read())

        XCTAssertNotNil(info.level)
        XCTAssertNotNil(info.externalPower)
    }
}
