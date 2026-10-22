import XCTest
@testable import WattyCore

final class NetFlowAccumulationTests: XCTestCase {
    private typealias Fixtures = NetFlowFixtures

    private struct Counter {
        private(set) var accumulation = PowerAccumulation(milliwattTicks: 2_500_000_000, ticks: 126_000)

        mutating func advance(seconds: Int, meanWatts: Double) {
            accumulation = PowerAccumulation(
                milliwattTicks: accumulation.milliwattTicks + Int64((meanWatts * 1_000).rounded()) * Int64(seconds),
                ticks: accumulation.ticks + Int64(seconds)
            )
        }
    }

    private func reading(
        _ seconds: TimeInterval,
        instantaneous: Double?,
        accumulation: PowerAccumulation?,
        adapter: Bool = true,
        charging: Bool = true
    ) -> NetFlowReading {
        NetFlowReading(
            date: Fixtures.origin.addingTimeInterval(seconds),
            batteryWatts: instantaneous,
            powerAccumulation: accumulation,
            level: 50,
            onAdapter: adapter,
            reportsCharging: charging
        )
    }

    private func feedMinuteRefreshes(
        into estimator: inout NetFlowEstimator,
        counter: inout Counter,
        from start: TimeInterval,
        minutes: Int,
        meanWatts: (Int) -> Double,
        instantaneousAtRefresh: (Int) -> Double,
        heldInstantaneous: Double,
        cadence: TimeInterval = Fixtures.visibleCadence,
        adapter: Bool = true,
        charging: Bool = true
    ) -> [(seconds: TimeInterval, estimate: NetFlowEstimate)] {
        var results: [(seconds: TimeInterval, estimate: NetFlowEstimate)] = []
        var instantaneous = heldInstantaneous
        let stepsPerMinute = Int(60 / cadence)
        for minute in 0..<minutes {
            for step in 0..<stepsPerMinute {
                let isRefresh = step == stepsPerMinute - 1
                if isRefresh {
                    counter.advance(seconds: 60, meanWatts: meanWatts(minute))
                    instantaneous = instantaneousAtRefresh(minute)
                }
                let seconds = start + Double(minute) * 60 + Double(step) * cadence
                let estimate = estimator.record(reading(
                    seconds, instantaneous: instantaneous, accumulation: counter.accumulation, adapter: adapter, charging: charging
                ))
                results.append((seconds, estimate))
            }
        }
        return results
    }

    func testTheAverageOfAMinuteOutweighsAStaleInstantaneousReading() throws {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        estimator.record(reading(0, instantaneous: 9, accumulation: counter.accumulation))

        let results = feedMinuteRefreshes(
            into: &estimator, counter: &counter, from: 2, minutes: 4,
            meanWatts: { _ in -20 }, instantaneousAtRefresh: { _ in 9 }, heldInstantaneous: 9
        )

        let beforeAnyChunk = results.first { $0.seconds >= NetFlowRules.Power.minimumInstantaneousSpan + 10 }
        XCTAssertEqual(beforeAnyChunk?.estimate.averageBatteryWatts ?? 0, 9, accuracy: 0.0001)
        XCTAssertEqual(beforeAnyChunk?.estimate.flow, .charging)
        let settled = try XCTUnwrap(results.last?.estimate)
        XCTAssertEqual(settled.flow, .draining)
        XCTAssertEqual(try XCTUnwrap(settled.averageBatteryWatts), -20, accuracy: 0.0001)
    }

    func testTheWindowWeighsEachMinuteByItsTicks() throws {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        estimator.record(reading(0, instantaneous: nil, accumulation: counter.accumulation))
        counter.advance(seconds: 60, meanWatts: -20)
        estimator.record(reading(61, instantaneous: nil, accumulation: counter.accumulation))
        counter.advance(seconds: 60, meanWatts: -20)
        estimator.record(reading(121, instantaneous: nil, accumulation: counter.accumulation))
        counter.advance(seconds: 20, meanWatts: 20)

        let estimate = estimator.record(reading(141, instantaneous: nil, accumulation: counter.accumulation))

        XCTAssertEqual(try XCTUnwrap(estimate.averageBatteryWatts), (-20.0 * 120 + 20 * 20) / 140, accuracy: 0.0001)
    }

    func testAMinuteThatStraddlesPluggingInIsNeverUsed() {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        var estimates: [NetFlowEstimate] = []
        estimator.record(reading(0, instantaneous: -20, accumulation: counter.accumulation, adapter: false, charging: false))
        counter.advance(seconds: 60, meanWatts: -20)
        estimator.record(reading(60, instantaneous: -20, accumulation: counter.accumulation, adapter: false, charging: false))

        counter.advance(seconds: 30, meanWatts: -20)
        estimates.append(estimator.record(reading(85, instantaneous: -20, accumulation: counter.accumulation)))
        counter.advance(seconds: 30, meanWatts: 30)
        estimates.append(estimator.record(reading(115, instantaneous: -20, accumulation: counter.accumulation)))
        counter.advance(seconds: 60, meanWatts: 30)
        estimates.append(estimator.record(reading(175, instantaneous: 30, accumulation: counter.accumulation)))
        counter.advance(seconds: 60, meanWatts: 30)
        estimates.append(estimator.record(reading(235, instantaneous: 30, accumulation: counter.accumulation)))

        XCTAssertFalse(estimates.contains { $0.flow == .draining })
        XCTAssertEqual(estimates.last?.flow, .charging)
        XCTAssertEqual(estimates.last?.averageBatteryWatts ?? 0, 30, accuracy: 0.0001)
    }

    func testWithoutNewTicksTheLastMinutesAgeOutOfTheWindowAndInstantaneousReadingsTakeOver() throws {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        estimator.record(reading(0, instantaneous: 30, accumulation: counter.accumulation))
        counter.advance(seconds: 60, meanWatts: -20)
        let drain = estimator.record(reading(60, instantaneous: 30, accumulation: counter.accumulation))

        var later = drain
        for seconds in stride(from: 62.0, through: 300, by: 2) {
            later = estimator.record(reading(seconds, instantaneous: 30, accumulation: counter.accumulation))
        }

        XCTAssertEqual(drain.flow, .draining)
        XCTAssertEqual(later.flow, .charging)
        XCTAssertEqual(try XCTUnwrap(later.averageBatteryWatts), 30, accuracy: 0.0001)
    }

    func testACounterThatGoesBackwardsRestartsTheBaselineWithoutAChunk() {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        estimator.record(reading(0, instantaneous: nil, accumulation: counter.accumulation))
        counter.advance(seconds: 60, meanWatts: -20)
        estimator.record(reading(60, instantaneous: nil, accumulation: counter.accumulation))
        let rebooted = PowerAccumulation(milliwattTicks: 5_000, ticks: 40)

        let afterReset = estimator.record(reading(62, instantaneous: nil, accumulation: rebooted))
        let nextRefresh = estimator.record(reading(122, instantaneous: nil, accumulation: PowerAccumulation(milliwattTicks: 5_000 + 60 * 25_000, ticks: 100)))

        XCTAssertEqual(afterReset.averageBatteryWatts ?? 0, -20, accuracy: 0.0001)
        XCTAssertEqual(nextRefresh.averageBatteryWatts ?? 0, -20, accuracy: 0.0001)
    }

    func testAChunkLongerThanTheLimitIsIgnored() {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        estimator.record(reading(0, instantaneous: 12, accumulation: counter.accumulation))
        counter.advance(seconds: Int(NetFlowRules.Accumulation.maximumChunkTicks) + 1, meanWatts: -20)

        let estimate = estimator.record(reading(60, instantaneous: 12, accumulation: counter.accumulation))

        XCTAssertEqual(estimate.averageBatteryWatts ?? 0, 12, accuracy: 0.0001)
    }

    func testAnImplausibleChunkIsIgnored() {
        var estimator = NetFlowEstimator()
        var counter = Counter()
        estimator.record(reading(0, instantaneous: 12, accumulation: counter.accumulation))
        counter.advance(seconds: 60, meanWatts: -900)

        let estimate = estimator.record(reading(60, instantaneous: 12, accumulation: counter.accumulation))

        XCTAssertEqual(estimate.averageBatteryWatts ?? 0, 12, accuracy: 0.0001)
    }

    func testReadingsWithoutAnAccumulatorKeepUsingTheInstantaneousAverage() {
        var estimator = NetFlowEstimator()
        let readings = Fixtures.steadyReadings(from: 0, through: 60, every: Fixtures.visibleCadence, watts: -14)

        for reading in readings { estimator.record(reading) }

        XCTAssertEqual(estimator.estimate.flow, .draining)
        XCTAssertEqual(estimator.estimate.averageBatteryWatts ?? 0, -14, accuracy: 0.0001)
    }

    func testTheRealMinuteThatFooledTheInstantaneousReading() throws {
        var estimator = NetFlowEstimator()
        let before = PowerAccumulation(milliwattTicks: 2_654_998_405 - 2_521_100_015, ticks: 126_428 + 166_233)
        let after = PowerAccumulation(milliwattTicks: 2_655_846_906 - 2_522_056_188, ticks: 126_466 + 166_255)
        estimator.record(reading(0, instantaneous: 28.374, accumulation: before))

        let estimate = estimator.record(reading(29, instantaneous: 27.808, accumulation: after))

        XCTAssertEqual(try XCTUnwrap(estimate.averageBatteryWatts), -1.7945, accuracy: 0.001)
        XCTAssertNotEqual(estimate.flow, .charging)
    }
}
