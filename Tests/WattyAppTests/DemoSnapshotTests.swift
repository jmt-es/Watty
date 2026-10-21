import XCTest
@testable import Watty
import WattyCore

final class DemoSnapshotTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ scenario: DemoScenario) -> BatterySnapshot {
        DemoSnapshot.make(for: scenario, at: date)
    }

    func testChargingScenarioHasTheDocumentedReadings() {
        let snapshot = snapshot(.charging)

        XCTAssertTrue(snapshot.hasBattery)
        XCTAssertEqual(snapshot.level, 76)
        XCTAssertEqual(snapshot.chargeState, .charging)
        XCTAssertEqual(snapshot.timeToFullMinutes, 48)
        XCTAssertEqual(snapshot.adapterRatedWatts, 70)
        XCTAssertEqual(snapshot.systemPowerWatts, 42.5)
        XCTAssertEqual(snapshot.systemLoadWatts, 21.3)
        XCTAssertEqual(snapshot.batteryPowerWatts, 19.8)
        XCTAssertEqual(snapshot.voltageVolts, 12.61)
        XCTAssertEqual(snapshot.amperageAmps, 1.57)
        XCTAssertEqual(snapshot.temperatureCelsius, 31.4)
        XCTAssertEqual(snapshot.cycleCount, 142)
        XCTAssertEqual(snapshot.maximumCapacityPercent, 94)
        XCTAssertEqual(snapshot.condition, "Normal")
        XCTAssertEqual(snapshot.powerMode, .automatic)
        XCTAssertEqual(snapshot.lowPowerModeActive, false)
    }

    func testBatteryScenarioIsDischargingAtAboutNineWatts() {
        let snapshot = snapshot(.battery)

        XCTAssertTrue(snapshot.hasBattery)
        XCTAssertEqual(snapshot.level, 58)
        XCTAssertEqual(snapshot.chargeState, .onBattery)
        XCTAssertEqual(snapshot.timeToEmptyMinutes, 4 * 60 + 12)
        XCTAssertNil(snapshot.timeToFullMinutes)
        XCTAssertNil(snapshot.adapterRatedWatts)
        XCTAssertEqual(snapshot.batteryPowerWatts, -9.1)
        XCTAssertEqual(snapshot.cycleCount, 142)
        XCTAssertEqual(snapshot.maximumCapacityPercent, 94)
    }

    func testDesktopScenarioHasNoBatteryAndNoPowerReadings() {
        let snapshot = snapshot(.desktop)

        XCTAssertFalse(snapshot.hasBattery)
        XCTAssertFalse(snapshot.isCharging)
        XCTAssertNil(snapshot.batteryPowerWatts)
        XCTAssertNil(snapshot.systemPowerWatts)
        XCTAssertNil(snapshot.systemLoadWatts)
        XCTAssertNil(snapshot.cycleCount)
        XCTAssertNil(snapshot.maximumCapacityPercent)
        XCTAssertNil(snapshot.condition)
        XCTAssertNil(snapshot.temperatureCelsius)
    }

    func testEveryScenarioOffersAllEnergyModesAndIsNeverEmpty() {
        for scenario in DemoScenario.allCases {
            let snapshot = snapshot(scenario)

            XCTAssertFalse(snapshot.isEmpty, "\(scenario)")
            XCTAssertEqual(snapshot.lastUpdated, date, "\(scenario)")
            XCTAssertEqual(snapshot.powerModeSupport.availableModes, [.automatic, .lowPower, .highPower], "\(scenario)")
            XCTAssertTrue(snapshot.warnings.isEmpty, "\(scenario)")
        }
    }

    func testRequestedEnergyModeIsReflected() {
        let snapshot = DemoSnapshot.make(for: .charging, at: date, powerMode: .lowPower)

        XCTAssertEqual(snapshot.powerMode, .lowPower)
        XCTAssertEqual(snapshot.lowPowerModeActive, true)
    }

    func testChargingFlowsAddUp() throws {
        let snapshot = snapshot(.charging)
        let input = try XCTUnwrap(snapshot.systemPowerWatts)
        let load = try XCTUnwrap(snapshot.systemLoadWatts)
        let battery = try XCTUnwrap(snapshot.batteryPowerWatts)
        let volts = try XCTUnwrap(snapshot.voltageVolts)
        let amps = try XCTUnwrap(snapshot.amperageAmps)

        XCTAssertEqual(volts * amps, battery, accuracy: 0.05)
        XCTAssertEqual(input, load + battery, accuracy: 3)
        XCTAssertLessThanOrEqual(input, Double(DemoSnapshot.adapterRatedWatts))
    }

    func testDischargeFlowsFollowTheSanitizedCoreContract() throws {
        let snapshot = snapshot(.battery)
        let load = try XCTUnwrap(snapshot.systemLoadWatts)
        let battery = try XCTUnwrap(snapshot.batteryPowerWatts)
        let volts = try XCTUnwrap(snapshot.voltageVolts)
        let amps = try XCTUnwrap(snapshot.amperageAmps)

        XCTAssertLessThan(battery, 0)
        XCTAssertLessThan(amps, 0)
        XCTAssertGreaterThanOrEqual(load, 0)
        XCTAssertEqual(volts * amps, battery, accuracy: 0.05)
        XCTAssertEqual(load, -battery, accuracy: 0.05)
    }

    func testThePanelReadsTheFlowsTheWayTheScenariosDescribeThem() {
        let charging = PowerFlowReading(snapshot: snapshot(.charging))
        let onBattery = PowerFlowReading(snapshot: snapshot(.battery))

        XCTAssertEqual(charging.batteryDirection, .charging)
        XCTAssertTrue(charging.adapterIsFeedingSystem)
        XCTAssertEqual(charging.systemLoadWatts, 21.3)
        XCTAssertEqual(onBattery.batteryDirection, .discharging)
        XCTAssertFalse(onBattery.adapterIsFeedingSystem)
        XCTAssertEqual(onBattery.systemLoadWatts, 9.1)
    }
}
