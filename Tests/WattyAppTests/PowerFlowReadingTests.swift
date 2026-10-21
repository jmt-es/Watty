import XCTest
@testable import Watty
import WattyCore

final class PowerFlowReadingTests: XCTestCase {
    private func snapshot(adapter: Bool, battery: Double? = nil, input: Double? = nil, load: Double? = nil) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = Date()
        snapshot.powerSource = adapter ? .adapter : .battery
        snapshot.batteryPowerWatts = battery
        snapshot.systemPowerWatts = input
        snapshot.systemLoadWatts = load
        return snapshot
    }

    func testChargingOnTheAdapterFeedsTheSystemAndTheBattery() {
        let reading = PowerFlowReading(snapshot: snapshot(adapter: true, battery: 20, input: 45, load: 25))

        XCTAssertEqual(reading.batteryDirection, .charging)
        XCTAssertEqual(reading.batteryWatts, 20)
        XCTAssertEqual(reading.systemLoadWatts, 25)
        XCTAssertTrue(reading.adapterIsFeedingSystem)
    }

    func testSystemLoadIsDerivedFromAdapterInputWhenMissing() {
        let reading = PowerFlowReading(snapshot: snapshot(adapter: true, battery: 15, input: 60))

        XCTAssertEqual(reading.systemLoadWatts, 45)
    }

    func testDischargingOnBatteryUsesTheDischargeAsSystemLoad() {
        let reading = PowerFlowReading(snapshot: snapshot(adapter: false, battery: -12.5))

        XCTAssertEqual(reading.batteryDirection, .discharging)
        XCTAssertEqual(reading.systemLoadWatts, 12.5)
        XCTAssertFalse(reading.adapterIsFeedingSystem)
    }

    func testSmallBatteryFlowsCountAsIdle() {
        XCTAssertEqual(PowerFlowReading(snapshot: snapshot(adapter: true, battery: 0.3, input: 20)).batteryDirection, .idle)
        XCTAssertEqual(PowerFlowReading(snapshot: snapshot(adapter: false, battery: -0.2)).batteryDirection, .idle)
        XCTAssertEqual(PowerFlowReading(snapshot: snapshot(adapter: true)).batteryDirection, .idle)
    }

    func testAdapterFlowNeedsMeaningfulInput() {
        XCTAssertFalse(PowerFlowReading(snapshot: snapshot(adapter: true, input: 0.2)).adapterIsFeedingSystem)
        XCTAssertFalse(PowerFlowReading(snapshot: snapshot(adapter: true)).adapterIsFeedingSystem)
        XCTAssertTrue(PowerFlowReading(snapshot: snapshot(adapter: true, input: 12)).adapterIsFeedingSystem)
    }

    func testUnknownReadingsStayUnknown() {
        let reading = PowerFlowReading(snapshot: snapshot(adapter: false))

        XCTAssertNil(reading.batteryWatts)
        XCTAssertNil(reading.systemLoadWatts)
    }
}
