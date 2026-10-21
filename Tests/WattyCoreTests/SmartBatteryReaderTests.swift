import XCTest
@testable import WattyCore

final class SmartBatteryReaderTests: XCTestCase {
    private func requireLiveProperties() throws -> [String: Any] {
        switch SmartBatteryReader.read() {
        case .properties(let properties):
            return properties
        case .noService:
            throw XCTSkip("No AppleSmartBattery service on this machine")
        case .failed(let reason):
            XCTFail("AppleSmartBattery exists but could not be read: \(reason)")
            throw XCTSkip("AppleSmartBattery unreadable")
        }
    }

    func testReadDistinguishesMissingServiceFromFailure() {
        switch SmartBatteryReader.read() {
        case .properties(let properties):
            XCTAssertFalse(properties.isEmpty)
        case .noService:
            break
        case .failed(let reason):
            XCTFail("Unexpected failure on a healthy machine: \(reason)")
        }
    }

    func testResultHelpersDescribeEachCase() {
        let present = SmartBatteryReadResult.properties(["CycleCount": 1])

        XCTAssertEqual(present.properties?["CycleCount"] as? Int, 1)
        XCTAssertTrue(present.serviceExists)
        XCTAssertNil(SmartBatteryReadResult.noService.properties)
        XCTAssertFalse(SmartBatteryReadResult.noService.serviceExists)
        XCTAssertNil(SmartBatteryReadResult.failed("boom").properties)
        XCTAssertTrue(SmartBatteryReadResult.failed("boom").serviceExists)
    }

    func testRepeatedReadsKeepSucceeding() throws {
        _ = try requireLiveProperties()

        for _ in 0..<25 {
            let properties = try XCTUnwrap(SmartBatteryReader.read().properties)
            XCTAssertFalse(properties.isEmpty)
        }
    }

    func testInProcessParseMatchesIoregTextForStableFields() throws {
        let properties = try requireLiveProperties()
        let ioreg = ProcessRunner().run(
            "/usr/sbin/ioreg",
            arguments: ["-l", "-n", SmartBatteryReader.serviceName, "-r"],
            timeout: 5
        )
        try XCTSkipUnless(ioreg.succeeded, "ioreg is not usable here")

        let inProcess = TelemetryParsers.parseSmartBatteryProperties(properties)
        let text = TelemetryParsers.parseIoregBattery(ioreg.stdout)

        XCTAssertEqual(inProcess.cycleCount, text.cycleCount)
        XCTAssertEqual(inProcess.maximumCapacityPercent, text.maximumCapacityPercent)
        XCTAssertEqual(inProcess.adapterRatedWatts, text.adapterRatedWatts)
        XCTAssertEqual(inProcess.externalConnected, text.externalConnected)
        XCTAssertEqual(inProcess.isCharging, text.isCharging)
        XCTAssertEqual(inProcess.isFullyCharged, text.isFullyCharged)

        XCTAssertEqual(inProcess.voltageVolts == nil, text.voltageVolts == nil, "voltage presence")
        XCTAssertEqual(inProcess.amperageAmps == nil, text.amperageAmps == nil, "amperage presence")
        XCTAssertEqual(inProcess.batteryPowerWatts == nil, text.batteryPowerWatts == nil, "battery power presence")
        XCTAssertEqual(inProcess.systemPowerWatts == nil, text.systemPowerWatts == nil, "system power presence")
        XCTAssertEqual(inProcess.systemLoadWatts == nil, text.systemLoadWatts == nil, "system load presence")
        XCTAssertEqual(inProcess.temperatureCelsius == nil, text.temperatureCelsius == nil, "temperature presence")
        XCTAssertEqual(inProcess.currentCapacityPercent == nil, text.currentCapacityPercent == nil, "charge presence")

        if let live = inProcess.voltageVolts, let reference = text.voltageVolts {
            XCTAssertEqual(live, reference, accuracy: 1.0)
        }
        if let live = inProcess.temperatureCelsius, let reference = text.temperatureCelsius {
            XCTAssertEqual(live, reference, accuracy: 5.0)
        }
        if let live = inProcess.currentCapacityPercent, let reference = text.currentCapacityPercent {
            XCTAssertEqual(Double(live), Double(reference), accuracy: 3.0)
        }
    }

    func testLiveSnapshotInputsAreComplete() throws {
        let properties = try requireLiveProperties()
        try XCTSkipIf(properties["BatteryInstalled"] as? Bool == false, "Battery bay is empty on this machine")

        let info = TelemetryParsers.parseSmartBatteryProperties(properties)

        XCTAssertNotNil(info.voltageVolts)
        XCTAssertNotNil(info.cycleCount)
        XCTAssertNotNil(info.externalConnected)
    }
}
