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

    private func draining(instantaneous: Double?, average: Double?, input: Double? = 19.7, load: Double? = 38) -> BatterySnapshot {
        var snapshot = snapshot(adapter: true, battery: instantaneous, input: input, load: load)
        snapshot.netFlow = NetFlowEstimate(flow: .draining, averageBatteryWatts: average)
        return snapshot
    }

    func testDrainingOnTheAdapterShowsTheAveragedPowerNotTheInstantaneousSpike() {
        let reading = PowerFlowReading(snapshot: draining(instantaneous: 4.8, average: -18.3))

        XCTAssertEqual(reading.batteryDirection, .draining)
        XCTAssertEqual(reading.batteryWatts, -18.3)
        XCTAssertTrue(reading.adapterIsFeedingSystem)
        XCTAssertEqual(reading.systemLoadWatts, 38)
    }

    func testDrainingWithoutAnAverageShowsNoWattsRatherThanAContradictingOne() {
        let reading = PowerFlowReading(snapshot: draining(instantaneous: 4.8, average: nil))

        XCTAssertEqual(reading.batteryDirection, .draining)
        XCTAssertNil(reading.batteryWatts)
    }

    func testOnBatteryTheDrainKeepsTheInstantaneousReading() {
        var onBattery = snapshot(adapter: false, battery: -12.5)
        onBattery.netFlow = NetFlowEstimate(flow: .draining, averageBatteryWatts: -3)

        let reading = PowerFlowReading(snapshot: onBattery)

        XCTAssertEqual(reading.batteryDirection, .discharging)
        XCTAssertEqual(reading.batteryWatts, -12.5)
    }

    func testTheOtherFlowsKeepTheInstantaneousReading() {
        for flow in [NetFlow.charging, .holding] {
            var charging = snapshot(adapter: true, battery: 20, input: 45, load: 25)
            charging.netFlow = NetFlowEstimate(flow: flow, averageBatteryWatts: 1)

            let reading = PowerFlowReading(snapshot: charging)

            XCTAssertEqual(reading.batteryDirection, .charging, "\(flow)")
            XCTAssertEqual(reading.batteryWatts, 20)
        }
    }

    func testTheSystemLoadAddsTheBatterySupplementWhenTheControllerDoesNotReportIt() {
        let reading = PowerFlowReading(snapshot: draining(instantaneous: -18.3, average: -18.3, load: nil))

        XCTAssertEqual(reading.systemLoadWatts ?? 0, 38, accuracy: 0.0001)
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
