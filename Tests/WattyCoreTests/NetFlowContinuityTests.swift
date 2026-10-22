import XCTest
@testable import WattyCore

final class NetFlowContinuityTests: XCTestCase {
    private typealias Fixtures = NetFlowFixtures

    private func historySample(
        _ seconds: TimeInterval,
        level: Int,
        charging: Bool = true,
        adapter: Bool = true
    ) -> BatteryHistorySample {
        BatteryHistorySample(
            date: Fixtures.origin.addingTimeInterval(seconds),
            level: level,
            isCharging: charging,
            onAdapter: adapter
        )
    }

    private func fallingHistory(throughSeconds seconds: TimeInterval) -> [BatteryHistorySample] {
        stride(from: 0.0, through: seconds, by: 60).map { historySample($0, level: 40 - Int($0 / 60)) }
    }

    func testPluggingInAfterDischargingDoesNotInheritTheDischargeOrTheStaleReadings() {
        var estimator = NetFlowEstimator()
        let onBattery = Fixtures.steadyReadings(from: 0, through: 300, every: Fixtures.visibleCadence, watts: -20, onAdapter: false, reportsCharging: false)
        let staleAfterPlugging = Fixtures.steadyReadings(from: 302, through: 362, every: Fixtures.visibleCadence, watts: -20)
        let fresh = Fixtures.steadyReadings(from: 364, through: 600, every: Fixtures.visibleCadence, watts: 30)
        for reading in onBattery { estimator.record(reading) }

        let flows = Fixtures.flows(staleAfterPlugging + fresh, using: &estimator)

        let settlingEnd = Int(NetFlowRules.Continuity.settlingTime / Fixtures.visibleCadence)
        XCTAssertTrue(flows.prefix(settlingEnd).allSatisfy { $0 == nil }, "\(flows.prefix(settlingEnd))")
        XCTAssertFalse(flows.contains(.draining))
        XCTAssertEqual(flows.last, .charging)
    }

    func testUnpluggingIsDrainingImmediately() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.steadyReadings(from: 0, through: 120, every: Fixtures.visibleCadence, watts: 30) {
            estimator.record(reading)
        }

        let flow = estimator.record(Fixtures.reading(at: 122, watts: 12, onAdapter: false, reportsCharging: false)).flow

        XCTAssertEqual(flow, .draining)
    }

    func testAnEstablishedDrainIsForgottenWhenTheAdapterChanges() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.incidentReadings(through: 120, every: Fixtures.visibleCadence) { estimator.record(reading) }
        let unplugged = estimator.record(Fixtures.reading(at: 122, watts: -20, onAdapter: false, reportsCharging: false))

        let replugged = estimator.record(Fixtures.reading(at: 130, watts: -20))

        XCTAssertEqual(unplugged.flow, .draining)
        XCTAssertNil(replugged.flow)
        XCTAssertNil(replugged.averageBatteryWatts)
    }

    func testTheEvidenceRestartsAfterAGapBecauseTheRegistryMayBeStale() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.incidentReadings(through: 180, every: Fixtures.visibleCadence) { estimator.record(reading) }
        let wakeUp = 180.0 + 3_600

        let atWake = estimator.record(Fixtures.reading(at: wakeUp, watts: -20))
        let stillSettling = estimator.record(Fixtures.reading(at: wakeUp + 60, watts: -20))
        let settled = Fixtures.steadyReadings(from: wakeUp + 92, through: wakeUp + 150, every: Fixtures.visibleCadence, watts: 25)
        let flows = Fixtures.flows(settled, using: &estimator)

        XCTAssertNil(atWake.flow)
        XCTAssertNil(stillSettling.flow)
        XCTAssertEqual(flows.last, .charging)
    }

    func testAGapShorterThanTheLimitKeepsTheEvidence() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.incidentReadings(through: 180, every: Fixtures.visibleCadence) { estimator.record(reading) }

        let afterShortGap = estimator.record(Fixtures.reading(at: 180 + NetFlowRules.Continuity.maximumReadingGap - 1, watts: -20, level: 22))

        XCTAssertEqual(afterShortGap.flow, .draining)
    }

    func testTheHiddenCadenceDoesNotCountAsAGap() {
        XCTAssertLessThan(Fixtures.hiddenCadence * 2, NetFlowRules.Continuity.maximumReadingGap)
    }

    func testTheSameReadingTwiceChangesNothing() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.incidentReadings(through: 60, every: Fixtures.visibleCadence) { estimator.record(reading) }
        let before = estimator.estimate
        let lastDate = Fixtures.origin.addingTimeInterval(60)

        let repeated = estimator.record(NetFlowReading(date: lastDate, batteryWatts: 40, level: 90, onAdapter: true, reportsCharging: true))

        XCTAssertEqual(repeated, before)
    }

    func testAReadingFromThePastRestartsTheEvidence() {
        var estimator = NetFlowEstimator()
        for reading in Fixtures.incidentReadings(through: 120, every: Fixtures.visibleCadence) { estimator.record(reading) }

        let fromThePast = estimator.record(Fixtures.reading(at: 10, watts: -20))

        XCTAssertNil(fromThePast.flow)
    }

    func testSeededHistoryKeepsTheLevelEvidenceAcrossARestart() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))

        XCTAssertEqual(estimator.estimate.flow, .draining)
        XCTAssertNil(estimator.estimate.averageBatteryWatts)
    }

    func testTheFirstLiveReadingAfterASeedIsDrainingWithoutWaitingForPowerEvidence() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))

        let first = estimator.record(Fixtures.reading(at: 485, watts: -18, level: 32))

        XCTAssertEqual(first.flow, .draining)
    }

    func testPowerEvidenceTakesOverFromTheSeedOnceThereIsEnoughOfIt() throws {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))

        estimator.record(Fixtures.reading(at: 485, watts: -18, level: 32))
        let later = estimator.record(Fixtures.reading(at: 485 + NetFlowRules.Power.minimumInstantaneousSpan, watts: -18, level: 32))

        XCTAssertEqual(later.flow, .draining)
        XCTAssertEqual(try XCTUnwrap(later.averageBatteryWatts), -18, accuracy: 0.0001)
    }

    func testAQuietSeedLeavesTheStateUnknownUntilThereIsPowerEvidence() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: stride(from: 0.0, through: 480, by: 60).map { historySample($0, level: 50) })

        XCTAssertNil(estimator.estimate.flow)
    }

    func testTheFirstLiveReadingWithinTheSaveIntervalOfTheSeedKeepsTheLevelEvidence() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))
        let afterAWhile = 480 + NetFlowRules.Continuity.maximumGapAfterSeed - 30

        let first = estimator.record(Fixtures.reading(at: afterAWhile, watts: nil, level: 20))

        XCTAssertEqual(first.flow, .draining)
        XCTAssertNotNil(first.levelTrendPointsPerMinute)
    }

    func testAReadingLongerThanTheSaveIntervalAfterTheSeedStartsOver() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))

        let first = estimator.record(Fixtures.reading(at: 480 + NetFlowRules.Continuity.maximumGapAfterSeed + 1, watts: nil, level: 20))

        XCTAssertNil(first.levelTrendPointsPerMinute)
        XCTAssertNil(first.flow)
    }

    func testAnEarlierReadingNeverKeepsTheSeedEvenWithinTheGap() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))

        let first = estimator.record(Fixtures.reading(at: 300, watts: nil, level: 33))

        XCTAssertNil(first.levelTrendPointsPerMinute)
    }

    func testTheFirstLiveReadingAfterAStaleSeedDoesNotWaitToSettle() {
        var estimator = NetFlowEstimator()
        estimator.seed(with: fallingHistory(throughSeconds: 480))
        let launch = 480.0 + 3_600

        estimator.record(Fixtures.reading(at: launch, watts: -18, level: 20))
        let second = estimator.record(Fixtures.reading(at: launch + NetFlowRules.Power.minimumInstantaneousSpan, watts: -18, level: 20))

        XCTAssertEqual(second.flow, .draining)
    }

    func testSeededSamplesFromAnotherAdapterStateAreNotMixedIn() {
        var estimator = NetFlowEstimator()
        let onBattery = stride(from: 0.0, through: 480, by: 60).map { historySample($0, level: 60 - Int($0 / 60), charging: false, adapter: false) }
        estimator.seed(with: onBattery)

        let pluggedIn = estimator.record(Fixtures.reading(at: 485, watts: 30, level: 52))

        XCTAssertNil(pluggedIn.levelTrendPointsPerMinute)
        XCTAssertNotEqual(pluggedIn.flow, .draining)
    }

    func testSeedingFromNothingChangesNothing() {
        var estimator = NetFlowEstimator()

        estimator.seed(with: [])

        XCTAssertEqual(estimator.estimate, .unknown)
    }

    func testInstantaneousEstimatesUseTheSingleReading() {
        func estimate(watts: Double?, charging: Bool = true, adapter: Bool = true) -> NetFlowEstimate {
            var snapshot = BatterySnapshot.empty
            snapshot.lastUpdated = Fixtures.origin
            snapshot.level = 40
            snapshot.isCharging = charging
            snapshot.powerSource = adapter ? .adapter : .battery
            snapshot.batteryPowerWatts = watts
            return NetFlowEstimator.instantaneousEstimate(for: snapshot)
        }

        XCTAssertEqual(estimate(watts: -18).flow, .draining)
        XCTAssertEqual(estimate(watts: -18).averageBatteryWatts, -18)
        XCTAssertEqual(estimate(watts: 30).flow, .charging)
        XCTAssertEqual(estimate(watts: 0.1).flow, .holding)
        XCTAssertEqual(estimate(watts: 0, charging: false).flow, .holding)
        XCTAssertNil(estimate(watts: nil).flow)
        XCTAssertEqual(estimate(watts: -9, charging: false, adapter: false).flow, .draining)
        XCTAssertEqual(NetFlowEstimator.instantaneousEstimate(for: .empty), .unknown)
    }
}
