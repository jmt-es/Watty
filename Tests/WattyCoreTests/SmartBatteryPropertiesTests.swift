import XCTest
@testable import WattyCore

final class SmartBatteryPropertiesTests: XCTestCase {
    private static let negativeThousandAsUnsigned: UInt64 = 18_446_744_073_709_550_616

    private func appleSiliconRegistry() -> [String: Any] {
        [
            "ExternalConnected": true,
            "IsCharging": true,
            "FullyCharged": false,
            "Voltage": 12_235,
            "AppleRawBatteryVoltage": 12_235,
            "InstantAmperage": 2_408,
            "Amperage": 2_408,
            "CurrentCapacity": 69,
            "MaxCapacity": 100,
            "CycleCount": 257,
            "AvgTimeToFull": 82,
            "AvgTimeToEmpty": 65_535,
            "AdapterDetails": [
                "Watts": 70,
                "Description": "pd charger",
                "AdapterVoltage": 20_000,
                "FamilyCode": UInt64(18_446_744_073_172_697_098)
            ] as [String: Any],
            "AppleRawAdapterDetails": [["Watts": 70, "Description": "pd charger"]],
            "PowerTelemetryData": [
                "SystemPowerIn": 66_070,
                "SystemLoad": 30_803,
                "BatteryPower": 35_267,
                "AccumulatedBatteryPower": 2_499_894_435,
                "AccumulatedBatteryDischarge": UInt64(18_446_744_071_437_973_810)
            ] as [String: Any],
            "BatteryData": [
                "AppleRawMaxCapacity": 5_368,
                "DesignCapacity": 6_249,
                "MaxCapacity": 100,
                "CurrentCapacity": 69,
                "FullyCharged": 0,
                "BatteryPower": 29_461
            ] as [String: Any],
            "ChargerData": ["IsCharging": 1] as [String: Any],
            SmartBatteryReader.childrenKey: [
                ["ID": 0, "BatteryData": ["Temperature": 3_709, "CycleCount": 257] as [String: Any]] as [String: Any]
            ]
        ]
    }

    func testParsesAppleSiliconRegistryLayout() throws {
        let info = TelemetryParsers.parseSmartBatteryProperties(appleSiliconRegistry())

        XCTAssertEqual(try XCTUnwrap(info.voltageVolts), 12.235, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(info.amperageAmps), 2.408, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(info.batteryPowerWatts), 12.235 * 2.408, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(info.systemPowerWatts), 66.07, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(info.systemLoadWatts), 30.803, accuracy: 0.0001)
        XCTAssertEqual(info.adapterRatedWatts, 70)
        XCTAssertEqual(info.adapterDescription, "pd charger")
        XCTAssertEqual(info.cycleCount, 257)
        XCTAssertEqual(try XCTUnwrap(info.temperatureCelsius), 37.09, accuracy: 0.0001)
        XCTAssertEqual(info.externalConnected, true)
        XCTAssertEqual(info.isCharging, true)
        XCTAssertEqual(info.isFullyCharged, false)
        XCTAssertEqual(info.maximumCapacityPercent, 86)
        XCTAssertEqual(info.currentCapacityPercent, 69)
        XCTAssertEqual(info.timeToFullMinutes, 82)
        XCTAssertNil(info.timeToEmptyMinutes)
    }

    func testDecodesTwosComplementFromEverySwiftRepresentation() throws {
        let representations: [(String, Any)] = [
            ("UInt64", Self.negativeThousandAsUnsigned),
            ("NSNumber(UInt64)", NSNumber(value: Self.negativeThousandAsUnsigned)),
            ("Int64", Int64(-1000)),
            ("Int", -1000),
            ("NSNumber(Int64)", NSNumber(value: Int64(-1000))),
            ("decimal text", "18446744073709550616"),
            ("signed text", "-1000")
        ]

        for (label, value) in representations {
            let info = TelemetryParsers.parseSmartBatteryProperties(["Voltage": 12_000, "InstantAmperage": value])

            XCTAssertEqual(try XCTUnwrap(info.amperageAmps), -1.0, accuracy: 0.0001, label)
            XCTAssertEqual(try XCTUnwrap(info.batteryPowerWatts), -12.0, accuracy: 0.0001, label)
        }
    }

    func testFallsBackToAmperageAndRawVoltageKeys() throws {
        let info = TelemetryParsers.parseSmartBatteryProperties(["AppleRawBatteryVoltage": 11_100, "Amperage": 500])

        XCTAssertEqual(try XCTUnwrap(info.voltageVolts), 11.1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(info.amperageAmps), 0.5, accuracy: 0.0001)
    }

    func testScalesTemperatureOnlyWhenReportedInCentidegrees() throws {
        XCTAssertEqual(try XCTUnwrap(TelemetryParsers.parseSmartBatteryProperties(["Temperature": 3_077]).temperatureCelsius), 30.77, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(TelemetryParsers.parseSmartBatteryProperties(["Temperature": 31]).temperatureCelsius), 31, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(TelemetryParsers.parseSmartBatteryProperties(["Temperature": 1_001]).temperatureCelsius), 10.01, accuracy: 0.0001)
        XCTAssertNil(TelemetryParsers.parseSmartBatteryProperties([:]).temperatureCelsius)
    }

    func testFindsTemperatureInChildRegistryEntries() throws {
        let properties: [String: Any] = [
            SmartBatteryReader.childrenKey: [
                ["BatteryData": ["VirtualTemperature": 9_999, "Temperature": 2_950] as [String: Any]] as [String: Any]
            ]
        ]

        let info = TelemetryParsers.parseSmartBatteryProperties(properties)

        XCTAssertEqual(try XCTUnwrap(info.temperatureCelsius), 29.5, accuracy: 0.0001)
    }

    func testTreatsSentinelAndNonPositiveMinutesAsUnknown() {
        let unknown = TelemetryParsers.parseSmartBatteryProperties(["AvgTimeToFull": 65_535, "AvgTimeToEmpty": 0])
        XCTAssertNil(unknown.timeToFullMinutes)
        XCTAssertNil(unknown.timeToEmptyMinutes)

        let negative = TelemetryParsers.parseSmartBatteryProperties(["AvgTimeToFull": UInt64.max, "AvgTimeToEmpty": -5])
        XCTAssertNil(negative.timeToFullMinutes)
        XCTAssertNil(negative.timeToEmptyMinutes)

        let known = TelemetryParsers.parseSmartBatteryProperties(["AvgTimeToFull": 48, "AvgTimeToEmpty": 65_534])
        XCTAssertEqual(known.timeToFullMinutes, 48)
        XCTAssertEqual(known.timeToEmptyMinutes, 65_534)
    }

    func testReadsSystemPowerFromNestedTelemetryDictionary() throws {
        let properties: [String: Any] = [
            "PowerTelemetryData": ["SystemPowerIn": 21_000, "SystemLoad": 19_000] as [String: Any]
        ]

        let info = TelemetryParsers.parseSmartBatteryProperties(properties)

        XCTAssertEqual(try XCTUnwrap(info.systemPowerWatts), 21.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(info.systemLoadWatts), 19.0, accuracy: 0.0001)
    }

    func testBatteryPowerDoesNotUseAccumulatedBatteryPower() throws {
        let withCurrent: [String: Any] = [
            "Voltage": 13_256,
            "InstantAmperage": 332,
            "PowerTelemetryData": ["AccumulatedBatteryPower": 66_001_807, "BatteryPower": 4_413] as [String: Any]
        ]
        XCTAssertEqual(
            try XCTUnwrap(TelemetryParsers.parseSmartBatteryProperties(withCurrent).batteryPowerWatts),
            4.400992,
            accuracy: 0.001
        )

        let telemetryOnly: [String: Any] = [
            "PowerTelemetryData": ["AccumulatedBatteryPower": 66_001_807, "BatteryPower": 4_413] as [String: Any]
        ]
        XCTAssertEqual(
            try XCTUnwrap(TelemetryParsers.parseSmartBatteryProperties(telemetryOnly).batteryPowerWatts),
            4.413,
            accuracy: 0.0001
        )

        let accumulatedOnly: [String: Any] = [
            "PowerTelemetryData": ["AccumulatedBatteryPower": 66_001_807] as [String: Any]
        ]
        XCTAssertNil(TelemetryParsers.parseSmartBatteryProperties(accumulatedOnly).batteryPowerWatts)
    }

    func testTelemetryBatteryPowerWinsOverSiblingBatteryDataBlock() throws {
        let properties: [String: Any] = [
            "BatteryData": ["BatteryPower": 29_461] as [String: Any],
            "PowerTelemetryData": ["BatteryPower": 35_267] as [String: Any]
        ]

        let info = TelemetryParsers.parseSmartBatteryProperties(properties)

        XCTAssertEqual(try XCTUnwrap(info.batteryPowerWatts), 35.267, accuracy: 0.0001)
    }

    func testRejectsImplausibleBatteryPower() throws {
        let impossibleProduct: [String: Any] = [
            "Voltage": 20_000,
            "InstantAmperage": 20_000,
            "PowerTelemetryData": ["BatteryPower": 5_000] as [String: Any]
        ]
        XCTAssertEqual(
            try XCTUnwrap(TelemetryParsers.parseSmartBatteryProperties(impossibleProduct).batteryPowerWatts),
            5.0,
            accuracy: 0.0001
        )

        let impossibleTelemetry: [String: Any] = [
            "PowerTelemetryData": ["BatteryPower": 300_000] as [String: Any]
        ]
        XCTAssertNil(TelemetryParsers.parseSmartBatteryProperties(impossibleTelemetry).batteryPowerWatts)
    }

    func testReadsAdapterFromDictionaryOrRawArray() {
        let rawOnly: [String: Any] = [
            "AppleRawAdapterDetails": [["Watts": 96, "Description": "usb pd"] as [String: Any]]
        ]
        let rawInfo = TelemetryParsers.parseSmartBatteryProperties(rawOnly)
        XCTAssertEqual(rawInfo.adapterRatedWatts, 96)
        XCTAssertEqual(rawInfo.adapterDescription, "usb pd")

        let both: [String: Any] = [
            "AdapterDetails": ["Watts": 140, "Description": "pd charger"] as [String: Any],
            "AppleRawAdapterDetails": [["Watts": 30, "Description": "other"] as [String: Any]]
        ]
        let bothInfo = TelemetryParsers.parseSmartBatteryProperties(both)
        XCTAssertEqual(bothInfo.adapterRatedWatts, 140)
        XCTAssertEqual(bothInfo.adapterDescription, "pd charger")

        let multiple: [String: Any] = [
            "AppleRawAdapterDetails": [
                ["Description": "no rating"] as [String: Any],
                ["Watts": 61, "Description": "second"] as [String: Any]
            ]
        ]
        let multipleInfo = TelemetryParsers.parseSmartBatteryProperties(multiple)
        XCTAssertEqual(multipleInfo.adapterRatedWatts, 61)
        XCTAssertEqual(multipleInfo.adapterDescription, "second")
    }

    func testUnpluggedAdapterEntriesYieldNoDescriptionOrRating() {
        let info = TelemetryParsers.parseSmartBatteryProperties(["AppleRawAdapterDetails": [Any](), "Description": "unrelated"])

        XCTAssertNil(info.adapterRatedWatts)
        XCTAssertNil(info.adapterDescription)
    }

    func testMissingKeysYieldAnEmptyInfo() {
        XCTAssertEqual(TelemetryParsers.parseSmartBatteryProperties([:]), IoregBatteryInfo())
        XCTAssertEqual(
            TelemetryParsers.parseSmartBatteryProperties(["Serial": "x", "BatteryData": [String: Any]()]),
            IoregBatteryInfo()
        )
    }

    func testTopLevelKeysWinOverNestedOnes() {
        let properties: [String: Any] = [
            "CycleCount": 10,
            "BatteryData": ["CycleCount": 99] as [String: Any]
        ]

        XCTAssertEqual(TelemetryParsers.parseSmartBatteryProperties(properties).cycleCount, 10)
    }

    func testNestedLookupIsBreadthFirstAndSortedForDeterminism() {
        let shallowBeatsDeep: [String: Any] = [
            "Alpha": ["Inner": ["CycleCount": 7] as [String: Any]] as [String: Any],
            "Zeta": ["CycleCount": 5] as [String: Any]
        ]
        XCTAssertEqual(TelemetryParsers.parseSmartBatteryProperties(shallowBeatsDeep).cycleCount, 5)

        let sortedSiblings: [String: Any] = [
            "Beta": ["CycleCount": 2] as [String: Any],
            "Alpha": ["CycleCount": 1] as [String: Any],
            "Gamma": ["CycleCount": 3] as [String: Any]
        ]
        for _ in 0..<20 {
            XCTAssertEqual(TelemetryParsers.parseSmartBatteryProperties(sortedSiblings).cycleCount, 1)
        }

        let insideArrays: [String: Any] = [
            "Entries": [["CycleCount": 4] as [String: Any], ["CycleCount": 8] as [String: Any]]
        ]
        XCTAssertEqual(TelemetryParsers.parseSmartBatteryProperties(insideArrays).cycleCount, 4)
    }

    func testMatchesKeysExactlyNeverBySubstring() {
        let lookalikes: [String: Any] = [
            "AccumulatedBatteryPower": 1_000,
            "VirtualTemperature": 4_500,
            "MaxCapacityRaw": 77,
            "NominalChargeCapacity": 5_000,
            "Voltages": 9_999,
            "CycleCountLastQmax": 250
        ]

        XCTAssertEqual(TelemetryParsers.parseSmartBatteryProperties(lookalikes), IoregBatteryInfo())
    }

    func testCapacityPercentFallsBackToReportedMaximum() {
        let reportedPercent = TelemetryParsers.parseSmartBatteryProperties(["MaxCapacity": 97, "CurrentCapacity": 48])
        XCTAssertEqual(reportedPercent.maximumCapacityPercent, 97)
        XCTAssertEqual(reportedPercent.currentCapacityPercent, 49)

        let milliampHours = TelemetryParsers.parseSmartBatteryProperties(["MaxCapacity": 5_000, "CurrentCapacity": 3_000])
        XCTAssertNil(milliampHours.maximumCapacityPercent)
        XCTAssertEqual(milliampHours.currentCapacityPercent, 60)

        let zeroDesign = TelemetryParsers.parseSmartBatteryProperties(["AppleRawMaxCapacity": 5_000, "DesignCapacity": 0, "MaxCapacity": 98])
        XCTAssertEqual(zeroDesign.maximumCapacityPercent, 98)
    }

    func testDoesNotTrapOnAbsurdCapacityValues() {
        let info = TelemetryParsers.parseSmartBatteryProperties([
            "AppleRawMaxCapacity": Int64.max,
            "DesignCapacity": 1,
            "CurrentCapacity": Int64.max,
            "MaxCapacity": 1
        ])

        XCTAssertNil(info.maximumCapacityPercent)
        XCTAssertNil(info.currentCapacityPercent)
    }

    func testReadsBooleansFromBoolIntegerAndTextValues() {
        let boolean = TelemetryParsers.parseSmartBatteryProperties(["ExternalConnected": true, "IsCharging": false, "FullyCharged": true])
        XCTAssertEqual(boolean.externalConnected, true)
        XCTAssertEqual(boolean.isCharging, false)
        XCTAssertEqual(boolean.isFullyCharged, true)

        let integers = TelemetryParsers.parseSmartBatteryProperties(["ExternalConnected": 1, "IsCharging": 0, "FullyCharged": NSNumber(value: 1)])
        XCTAssertEqual(integers.externalConnected, true)
        XCTAssertEqual(integers.isCharging, false)
        XCTAssertEqual(integers.isFullyCharged, true)

        let text = TelemetryParsers.parseSmartBatteryProperties(["ExternalConnected": "Yes", "IsCharging": "No", "FullyCharged": "maybe"])
        XCTAssertEqual(text.externalConnected, true)
        XCTAssertEqual(text.isCharging, false)
        XCTAssertNil(text.isFullyCharged)
    }

    func testSkipsValuesOfTheWrongTypeAndKeepsLooking() throws {
        let properties: [String: Any] = [
            "Voltage": "not a number",
            "AppleRawBatteryVoltage": 12_000,
            "CycleCount": Data([0x01, 0x02]),
            "Nested": ["CycleCount": 33] as [String: Any],
            "Description": 5,
            "AdapterDetails": ["Watts": true, "Description": 7] as [String: Any]
        ]

        let info = TelemetryParsers.parseSmartBatteryProperties(properties)

        XCTAssertEqual(try XCTUnwrap(info.voltageVolts), 12.0, accuracy: 0.0001)
        XCTAssertEqual(info.cycleCount, 33)
        XCTAssertNil(info.adapterRatedWatts)
        XCTAssertNil(info.adapterDescription)
    }

    func testAgreesWithTheTextParserOnEquivalentRegistryContent() {
        let text = #"""
        "Voltage" = 12000
        "InstantAmperage" = 18446744073709550616
        "ExternalConnected" = No
        "IsCharging" = No
        "FullyCharged" = No
        "CycleCount" = 121
        "AppleRawMaxCapacity" = 5969
        "DesignCapacity" = 6249
        "Temperature" = 3077
        "CurrentCapacity" = 84
        "MaxCapacity" = 100
        "AvgTimeToEmpty" = 65535
        "AvgTimeToFull" = 48
        "PowerTelemetryData" = {"SystemPowerIn"=21000,"SystemLoad"=19000,"BatteryPower"=18446744073709546616}
        "AdapterDetails" = {"Watts"=100,"Description"="pd charger"}
        """#
        let properties: [String: Any] = [
            "Voltage": 12_000,
            "InstantAmperage": Self.negativeThousandAsUnsigned,
            "ExternalConnected": false,
            "IsCharging": false,
            "FullyCharged": false,
            "CycleCount": 121,
            "AppleRawMaxCapacity": 5_969,
            "DesignCapacity": 6_249,
            "Temperature": 3_077,
            "CurrentCapacity": 84,
            "MaxCapacity": 100,
            "AvgTimeToEmpty": 65_535,
            "AvgTimeToFull": 48,
            "PowerTelemetryData": [
                "SystemPowerIn": 21_000,
                "SystemLoad": 19_000,
                "BatteryPower": UInt64(18_446_744_073_709_546_616)
            ] as [String: Any],
            "AdapterDetails": ["Watts": 100, "Description": "pd charger"] as [String: Any]
        ]

        XCTAssertEqual(
            TelemetryParsers.parseSmartBatteryProperties(properties),
            TelemetryParsers.parseIoregBattery(text)
        )
    }
}
