import XCTest
@testable import WattyCore

final class NetFlowDecisionTests: XCTestCase {
    private let falling = LevelTrend(pointsPerMinute: -1, spanSeconds: 480)
    private let rising = LevelTrend(pointsPerMinute: 0.5, spanSeconds: 480)
    private let steady = LevelTrend(pointsPerMinute: 0, spanSeconds: 480)

    private func flow(
        watts: Double?,
        trend: LevelTrend? = nil,
        charging: Bool = true,
        adapter: Bool = true,
        previous: NetFlow? = nil
    ) -> NetFlow? {
        NetFlowDecision.flow(
            onAdapter: adapter,
            reportsCharging: charging,
            evidence: NetFlowEvidence(averageWatts: watts, trend: trend),
            previous: previous
        )
    }

    func testOnBatteryTheBatteryOnlyDrains() {
        XCTAssertEqual(flow(watts: 12, charging: false, adapter: false), .draining)
        XCTAssertEqual(flow(watts: nil, charging: false, adapter: false), .draining)
    }

    func testDrainingNeedsTheAverageToReachTheEnterThreshold() {
        let enter = NetFlowRules.Power.drainingEnterWatts

        XCTAssertEqual(flow(watts: enter + 0.01), .holding)
        XCTAssertEqual(flow(watts: enter), .draining)
        XCTAssertEqual(flow(watts: -20), .draining)
    }

    func testAnEstablishedDrainEndsOnlyAtTheExitThreshold() {
        let exit = NetFlowRules.Power.drainingExitWatts

        XCTAssertEqual(flow(watts: exit - 0.01, previous: .draining), .draining)
        XCTAssertEqual(flow(watts: exit, previous: .draining), .draining)
        XCTAssertEqual(flow(watts: exit + 0.01, previous: .draining), .holding)
        XCTAssertEqual(flow(watts: exit + 5, previous: .draining), .charging)
    }

    func testTheExitThresholdIsAboveTheEnterThreshold() {
        XCTAssertGreaterThan(NetFlowRules.Power.drainingExitWatts, NetFlowRules.Power.drainingEnterWatts)
        XCTAssertLessThan(NetFlowRules.Power.chargingExitWatts, NetFlowRules.Power.chargingEnterWatts)
    }

    func testChargingNeedsMacOSToSayItIsChargingAndPowerGoingIn() {
        let enter = NetFlowRules.Power.chargingEnterWatts

        XCTAssertEqual(flow(watts: enter), .charging)
        XCTAssertEqual(flow(watts: enter - 0.01), .holding)
        XCTAssertEqual(flow(watts: 25, charging: false), .holding)
    }

    func testAnEstablishedChargeEndsOnlyAtTheExitThreshold() {
        let exit = NetFlowRules.Power.chargingExitWatts

        XCTAssertEqual(flow(watts: exit, previous: .charging), .charging)
        XCTAssertEqual(flow(watts: exit - 0.01, previous: .charging), .holding)
    }

    func testMacOSNotChargingWithoutADrainIsHolding() {
        XCTAssertEqual(flow(watts: 0, charging: false), .holding)
        XCTAssertEqual(flow(watts: -1, charging: false), .holding)
    }

    func testARisingLevelVetoesAMarginalDrain() {
        XCTAssertEqual(flow(watts: -3, trend: rising), .holding)
        XCTAssertEqual(flow(watts: -3, trend: steady), .draining)
        XCTAssertEqual(flow(watts: -3, trend: falling), .draining)
    }

    func testAStrongDrainIgnoresALevelThatIsStillRisingFromEarlier() {
        XCTAssertEqual(flow(watts: NetFlowRules.Power.strongDrainingWatts - 1, trend: rising), .draining)
    }

    func testTheLevelDoesNotOverrideAnAveragedPowerThatSaysCharging() {
        XCTAssertEqual(flow(watts: 20, trend: falling), .charging)
        XCTAssertEqual(flow(watts: 0.1, trend: falling), .holding)
    }

    func testWithoutPowerAFallingLevelIsDraining() {
        XCTAssertEqual(flow(watts: nil, trend: falling), .draining)
        XCTAssertEqual(flow(watts: nil, trend: falling, charging: false), .draining)
    }

    func testWithoutPowerARisingLevelIsChargingOnlyIfMacOSAgrees() {
        XCTAssertEqual(flow(watts: nil, trend: rising), .charging)
        XCTAssertEqual(flow(watts: nil, trend: rising, charging: false), .holding)
    }

    func testWithoutPowerASteadyLevelIsUnknownWhileMacOSSaysChargingAndHoldingOtherwise() {
        XCTAssertNil(flow(watts: nil, trend: steady))
        XCTAssertEqual(flow(watts: nil, trend: steady, charging: false), .holding)
        XCTAssertNil(flow(watts: nil, trend: nil))
        XCTAssertEqual(flow(watts: nil, trend: nil, charging: false), .holding)
    }

    func testWithoutPowerADrainEndsWhenTheLevelStopsFalling() {
        let slowing = LevelTrend(pointsPerMinute: -0.2, spanSeconds: 480)

        XCTAssertEqual(flow(watts: nil, trend: slowing, previous: .draining), .draining)
        XCTAssertNil(flow(watts: nil, trend: slowing, previous: nil))
        XCTAssertNil(flow(watts: nil, trend: steady, previous: .draining))
    }
}
