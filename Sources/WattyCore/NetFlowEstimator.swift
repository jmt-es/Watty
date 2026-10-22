import Foundation

public struct NetFlowEstimator: Sendable {
    public private(set) var estimate = NetFlowEstimate.unknown

    private var onAdapter: Bool?
    private var lastDate: Date?
    private var settlingUntil: Date?
    private var followsSeed = false
    private var power = PowerSeries()
    private var levels = LevelSeries()
    private var flow: NetFlow?

    public init() {}

    @discardableResult
    public mutating func record(_ reading: NetFlowReading) -> NetFlowEstimate {
        if reading.date == lastDate { return estimate }

        if startsNewEvidence(with: reading) {
            discardEvidence(restartingPowerWith: reading.powerAccumulation)
            if !followsSeed {
                settlingUntil = reading.date.addingTimeInterval(NetFlowRules.Continuity.settlingTime)
            }
        } else if let accumulation = reading.powerAccumulation {
            power.observe(accumulation, at: reading.date)
        }
        followsSeed = false
        onAdapter = reading.onAdapter
        lastDate = reading.date

        levels.append(LevelPoint(date: reading.date, level: reading.level))
        if let watts = reading.batteryWatts, watts.isFinite, !isSettling(at: reading.date) {
            power.append(TimedValue(date: reading.date, value: watts))
        }

        let evidence = NetFlowEvidence(
            averageWatts: power.average(endingAt: reading.date),
            trend: LevelTrend.estimate(from: levels)
        )
        flow = NetFlowDecision.flow(
            onAdapter: reading.onAdapter,
            reportsCharging: reading.reportsCharging,
            evidence: evidence,
            previous: flow
        )
        estimate = NetFlowEstimate(
            flow: flow,
            averageBatteryWatts: evidence.averageWatts,
            levelTrendPointsPerMinute: evidence.trend?.pointsPerMinute
        )
        return estimate
    }

    public mutating func seed(with samples: [BatteryHistorySample]) {
        seed(withReadings: samples.map { sample in
            NetFlowReading(
                date: sample.date,
                batteryWatts: nil,
                level: sample.level,
                onAdapter: sample.onAdapter,
                reportsCharging: sample.isCharging
            )
        })
    }

    public mutating func seed(withReadings readings: [NetFlowReading]) {
        for reading in readings.sorted(by: { $0.date < $1.date }) {
            record(reading)
        }
        followsSeed = true
    }

    @discardableResult
    public mutating func record(_ snapshot: BatterySnapshot) -> NetFlowEstimate {
        guard let reading = NetFlowReading(snapshot: snapshot) else {
            self = NetFlowEstimator()
            return .unknown
        }
        return record(reading)
    }

    public static func instantaneousEstimate(for snapshot: BatterySnapshot) -> NetFlowEstimate {
        guard let reading = NetFlowReading(snapshot: snapshot) else { return .unknown }
        let flow = NetFlowDecision.flow(
            onAdapter: reading.onAdapter,
            reportsCharging: reading.reportsCharging,
            evidence: NetFlowEvidence(averageWatts: reading.batteryWatts, trend: nil),
            previous: nil
        )
        return NetFlowEstimate(flow: flow, averageBatteryWatts: reading.batteryWatts)
    }

    private func startsNewEvidence(with reading: NetFlowReading) -> Bool {
        if let onAdapter, onAdapter != reading.onAdapter { return true }
        guard let lastDate else { return false }
        let elapsed = reading.date.timeIntervalSince(lastDate)
        let maximumGap = followsSeed ? NetFlowRules.Continuity.maximumGapAfterSeed : NetFlowRules.Continuity.maximumReadingGap
        return elapsed < 0 || elapsed > maximumGap
    }

    private func isSettling(at date: Date) -> Bool {
        guard let settlingUntil else { return false }
        return date < settlingUntil
    }

    private mutating func discardEvidence(restartingPowerWith accumulation: PowerAccumulation?) {
        power.restart(with: accumulation)
        levels.removeAll()
        flow = nil
    }
}
