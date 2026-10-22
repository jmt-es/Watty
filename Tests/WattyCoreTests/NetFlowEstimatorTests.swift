import XCTest
@testable import WattyCore

final class NetFlowEstimatorTests: XCTestCase {
    private typealias Fixtures = NetFlowFixtures

    func testTheRealIncidentAtTheVisibleCadenceIsDrainingOnceThereIsHalfAMinuteOfReadings() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.incidentReadings(through: 600, every: Fixtures.visibleCadence)

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertTrue(flows.prefix(Fixtures.visibleWarmUpReadings).allSatisfy { $0 == nil })
        for (index, flow) in flows.enumerated().dropFirst(Fixtures.visibleWarmUpReadings) {
            XCTAssertEqual(flow, .draining, "at \(Double(index) * Fixtures.visibleCadence) s")
        }
    }

    func testTheRealIncidentAtTheHiddenCadenceIsDrainingFromTheSecondReading() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.incidentReadings(through: 1_200, every: Fixtures.hiddenCadence)

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertNil(flows[0])
        XCTAssertTrue(flows.dropFirst().allSatisfy { $0 == .draining }, "\(flows)")
    }

    func testTheAveragedPowerOfTheIncidentIgnoresThePositiveSpikes() throws {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.incidentReadings(through: 300, every: Fixtures.visibleCadence)

        for reading in readings { estimator.record(reading) }

        let average = try XCTUnwrap(estimator.estimate.averageBatteryWatts)
        XCTAssertLessThan(average, -15)
        XCTAssertGreaterThan(average, -25)
    }

    func testTheFallingLevelOfTheIncidentIsReportedAsATrend() throws {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.incidentReadings(through: 600, every: Fixtures.visibleCadence)

        for reading in readings { estimator.record(reading) }

        let trend = try XCTUnwrap(estimator.estimate.levelTrendPointsPerMinute)
        XCTAssertLessThan(trend, -0.5)
    }

    func testTheIncidentIsDrainingEvenIfMacOSStopsSayingItIsCharging() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.incidentReadings(through: 120, every: Fixtures.visibleCadence).map {
            NetFlowReading(date: $0.date, batteryWatts: $0.batteryWatts, level: $0.level, onAdapter: true, reportsCharging: false)
        }

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertEqual(flows.last, .draining)
    }

    func testRealChargingIsCharging() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(
            from: 0, through: 600, every: Fixtures.visibleCadence, watts: 30,
            level: { 40 + Int($0 / 60) }
        )

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertTrue(flows.dropFirst(Fixtures.visibleWarmUpReadings).allSatisfy { $0 == .charging }, "\(flows)")
        XCTAssertEqual(estimator.estimate.averageBatteryWatts ?? 0, 30, accuracy: 0.0001)
    }

    func testRealChargingAtTheHiddenCadenceIsCharging() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(from: 0, through: 900, every: Fixtures.hiddenCadence, watts: 24)

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertNil(flows[0])
        XCTAssertTrue(flows.dropFirst().allSatisfy { $0 == .charging }, "\(flows)")
    }

    func testAFullBatteryHoldingAtOneHundredPercentIsHolding() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(
            from: 0, through: 300, every: Fixtures.visibleCadence, watts: 0.1,
            level: { _ in 100 }, reportsCharging: false
        )

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertTrue(flows.allSatisfy { $0 == .holding }, "\(flows)")
    }

    func testPluggedInWithMacOSNotChargingHoldsEvenWithoutPowerReadings() {
        var estimator = NetFlowEstimator()

        let flow = estimator.record(Fixtures.reading(at: 0, watts: nil, level: 80, reportsCharging: false)).flow

        XCTAssertEqual(flow, .holding)
    }

    func testBalancedPowerWhileMacOSSaysChargingIsHolding() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(from: 0, through: 120, every: Fixtures.visibleCadence, watts: 0.1)

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertEqual(flows.last, .holding)
    }

    func testTheChargerCannotKeepUpEvenWhenMacOSDoesNotReportCharging() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(
            from: 0, through: 60, every: Fixtures.visibleCadence, watts: -12, reportsCharging: false
        )

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertEqual(flows.last, .draining)
    }

    func testOnBatteryIsDrainingFromTheFirstReadingWithOrWithoutPower() {
        var withPower = NetFlowEstimator()
        var withoutPower = NetFlowEstimator()

        XCTAssertEqual(withPower.record(Fixtures.reading(at: 0, watts: -9, onAdapter: false, reportsCharging: false)).flow, .draining)
        XCTAssertEqual(withoutPower.record(Fixtures.reading(at: 0, watts: nil, onAdapter: false, reportsCharging: false)).flow, .draining)
    }

    func testNoPowerAndNoLevelEvidenceWhileMacOSSaysChargingIsUnknown() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(from: 0, through: 600, every: Fixtures.hiddenCadence, watts: nil)

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertTrue(flows.allSatisfy { $0 == nil }, "\(flows)")
    }

    func testWithoutPowerAFallingLevelIsDraining() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(
            from: 0, through: 600, every: Fixtures.hiddenCadence, watts: nil,
            level: { 60 - Int($0 / 60) }
        )

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertEqual(flows.last, .draining)
        XCTAssertNil(estimator.estimate.averageBatteryWatts)
    }

    func testWithoutPowerARisingLevelWhileChargingIsCharging() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(
            from: 0, through: 600, every: Fixtures.hiddenCadence, watts: nil,
            level: { 40 + Int($0 / 60) }
        )

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertEqual(flows.last, .charging)
    }

    func testHoveringAroundBalanceDoesNotFlicker() {
        var estimator = NetFlowEstimator()
        let noise = [1.4, -1.5, 0.9, -1.3, 1.2, -0.8, 1.5, -1.4]
        let readings = (0...900).map { index in
            Fixtures.reading(at: Double(index) * Fixtures.visibleCadence, watts: -1.1 + noise[index % noise.count], level: 8)
        }

        let flows = Fixtures.flows(readings, using: &estimator)

        XCTAssertLessThanOrEqual(Fixtures.changeCount(in: flows), 1, "\(Fixtures.changeCount(in: flows)) changes")
        XCTAssertFalse(flows.contains(.draining))
    }

    func testASlowSwingInsideTheHysteresisBandNeverLeavesAnEstablishedDrain() {
        var estimator = NetFlowEstimator()
        let drain = Fixtures.steadyReadings(from: 0, through: 240, every: Fixtures.visibleCadence, watts: -10)
        let hover = (121...600).map { index in
            Fixtures.reading(at: Double(index) * Fixtures.visibleCadence, watts: -1.2 + 0.6 * sin(Double(index) / 20), level: 8)
        }

        let flows = Fixtures.flows(drain + hover, using: &estimator)

        XCTAssertTrue(flows.dropFirst(Fixtures.visibleWarmUpReadings).allSatisfy { $0 == .draining })
    }

    func testTheSameHoverFromAFreshStartIsNotADrain() {
        var estimator = NetFlowEstimator()
        let hover = (0...480).map { index in
            Fixtures.reading(at: Double(index) * Fixtures.visibleCadence, watts: -1.2 + 0.6 * sin(Double(index) / 20), level: 8)
        }

        let flows = Fixtures.flows(hover, using: &estimator)

        XCTAssertFalse(flows.contains(.draining))
    }

    func testTheDrainEndsOnceTheAverageRecoversAfterTheLoadStops() {
        var estimator = NetFlowEstimator()
        let drain = Fixtures.steadyReadings(from: 0, through: 300, every: Fixtures.visibleCadence, watts: -20)
        let recovery = Fixtures.steadyReadings(from: 302, through: 900, every: Fixtures.visibleCadence, watts: 25)

        let flows = Fixtures.flows(drain + recovery, using: &estimator)

        XCTAssertEqual(flows[drain.count - 1], .draining)
        XCTAssertEqual(flows.last, .charging)
        XCTAssertEqual(Fixtures.changeCount(in: flows.dropFirst(drain.count - 1).map { $0 }), 2)
    }

    func testASinglePositiveSpikeDoesNotEndAnEstablishedDrain() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.steadyReadings(from: 0, through: 300, every: Fixtures.visibleCadence, watts: -20) {
            estimator.record(reading)
        }

        let afterSpike = estimator.record(Fixtures.reading(at: 302, watts: 6))

        XCTAssertEqual(afterSpike.flow, .draining)
    }

    func testNonFiniteReadingsAreIgnoredInsteadOfPoisoningTheAverage() throws {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(from: 0, through: 120, every: Fixtures.visibleCadence, watts: -15)

        for (index, reading) in readings.enumerated() {
            let poisoned = index % 5 == 0
                ? NetFlowReading(date: reading.date, batteryWatts: index % 10 == 0 ? .nan : .infinity, level: reading.level, onAdapter: true, reportsCharging: true)
                : reading
            estimator.record(poisoned)
        }

        XCTAssertEqual(estimator.estimate.flow, .draining)
        XCTAssertEqual(try XCTUnwrap(estimator.estimate.averageBatteryWatts), -15, accuracy: 0.5)
    }

    func testReadingsWithoutABatteryAreNotEstimated() {
        var snapshot = BatterySnapshot.empty
        snapshot.hasBattery = false
        snapshot.lastUpdated = NetFlowFixtures.origin

        XCTAssertNil(NetFlowReading(snapshot: snapshot))
        XCTAssertNil(NetFlowReading(snapshot: .empty))
    }

    func testTheSnapshotInitializerCopiesTheEvidence() throws {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = NetFlowFixtures.origin
        snapshot.level = 18
        snapshot.isCharging = true
        snapshot.powerSource = .adapter
        snapshot.batteryPowerWatts = -17.5

        let reading = try XCTUnwrap(NetFlowReading(snapshot: snapshot))

        XCTAssertEqual(reading, NetFlowReading(date: NetFlowFixtures.origin, batteryWatts: -17.5, level: 18, onAdapter: true, reportsCharging: true))
    }

    func testEstimatingASnapshotWithoutABatteryForgetsEverything() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.incidentReadings(through: 60, every: Fixtures.visibleCadence) { estimator.record(reading) }
        var desktop = BatterySnapshot.empty
        desktop.hasBattery = false
        desktop.lastUpdated = NetFlowFixtures.origin.addingTimeInterval(62)

        let estimate = estimator.record(desktop)

        XCTAssertEqual(estimate, .unknown)
        XCTAssertEqual(estimator.estimate, .unknown)
    }
}
