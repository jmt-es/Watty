import XCTest
@testable import WattyCore

final class ChargeStateTests: XCTestCase {
    private func snapshot(
        charging: Bool = true,
        adapter: Bool = true,
        full: Bool = false,
        level: Int = 18,
        flow: NetFlow? = nil
    ) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.level = level
        snapshot.isCharging = charging
        snapshot.isFullyCharged = full
        snapshot.powerSource = adapter ? .adapter : .battery
        snapshot.netFlow = NetFlowEstimate(flow: flow)
        return snapshot
    }

    func testPluggedInAndDrainingOverridesWhatMacOSReports() {
        let draining = snapshot(flow: .draining)

        XCTAssertEqual(draining.chargeState, .pluggedInDraining)
        XCTAssertEqual(draining.reportedChargeState, .charging)
        XCTAssertTrue(draining.isDrainingOnAdapter)
    }

    func testDrainingOverridesPluggedInNotChargingAndFullToo() {
        XCTAssertEqual(snapshot(charging: false, flow: .draining).chargeState, .pluggedInDraining)
        XCTAssertEqual(snapshot(charging: false, full: true, level: 100, flow: .draining).chargeState, .pluggedInDraining)
        XCTAssertEqual(snapshot(charging: false, full: true, level: 100, flow: .draining).reportedChargeState, .charged)
    }

    func testOnBatteryTheDrainIsNotAPluggedInDrain() {
        let onBattery = snapshot(charging: false, adapter: false, flow: .draining)

        XCTAssertEqual(onBattery.chargeState, .onBattery)
        XCTAssertFalse(onBattery.isDrainingOnAdapter)
    }

    func testTheOtherFlowsLeaveTheReportedStateAlone() {
        for flow in [nil, NetFlow.charging, .holding] {
            XCTAssertEqual(snapshot(flow: flow).chargeState, .charging, "\(String(describing: flow))")
            XCTAssertEqual(snapshot(charging: false, flow: flow).chargeState, .pluggedInNotCharging)
            XCTAssertEqual(snapshot(charging: false, full: true, level: 100, flow: flow).chargeState, .charged)
        }
    }

    func testBeforeTheFirstReadingTheStateIsUnknown() {
        var empty = BatterySnapshot.empty
        empty.netFlow = NetFlowEstimate(flow: .draining)

        XCTAssertEqual(empty.chargeState, .unknown)
    }

    func testEveryStateHasADistinctEnglishTitle() {
        let states: [ChargeState] = [.charging, .charged, .pluggedInNotCharging, .pluggedInDraining, .onBattery, .unknown]

        XCTAssertEqual(Set(states.map(\.title)).count, states.count)
        XCTAssertEqual(ChargeState.pluggedInDraining.title, "Plugged in, draining")
    }
}
